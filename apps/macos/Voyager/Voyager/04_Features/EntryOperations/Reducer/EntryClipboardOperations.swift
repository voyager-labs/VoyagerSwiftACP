import AppKit
import ComposableArchitecture
import Foundation

struct EntryViewLayoutCutClearMonitor: Sendable {
    var heuristic: EntryViewLayoutCutClearHeuristic

    struct RuntimeContext: Sendable {
        var now: Date
        var readPasteboardChangeCount: @Sendable () -> Int
        var readPasteboardCutSessionId: @Sendable () -> String?
        var fileExists: @Sendable (String) -> Bool
    }

    enum Decision: Equatable, Sendable {
        case noop
        case keep(EntryViewLayoutCutClearHeuristic.CutSession)
        case clear
    }

    init(heuristic: EntryViewLayoutCutClearHeuristic = .init()) {
        self.heuristic = heuristic
    }

    func evaluateOnAppDidBecomeActive(
        clipboardOperation: ClipboardOperation,
        clipboardItems: [String],
        session: EntryViewLayoutCutClearHeuristic.CutSession?,
        makeSession: (_ now: Date, _ sourcePaths: [String]) -> EntryViewLayoutCutClearHeuristic.CutSession?,
        context: RuntimeContext,
    ) -> Decision {
        guard clipboardOperation == .cut, !clipboardItems.isEmpty else {
            return .noop
        }

        guard let activeSession = session ?? makeSession(context.now, clipboardItems) else {
            return .clear
        }

        switch heuristic.evaluate(
            session: activeSession,
            now: context.now,
            readPasteboardChangeCount: context.readPasteboardChangeCount,
            readPasteboardCutSessionId: context.readPasteboardCutSessionId,
            fileExists: context.fileExists,
        ) {
        case let .keep(updatedSession):
            return .keep(updatedSession)
        case .clear:
            return .clear
        }
    }
}

@Reducer
struct EntryClipboardOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.pasteboardClient)
    var pasteboardClient
    @Dependency(\.uuid)
    var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .clipboard(.copySelectedItems(files)):
                state.clipboardItems = files.map(\.fullPath)
                state.clipboardOperation = .copy
                state.cutClearSession = nil
                entryFileOpsClient.saveClipboardCutSessionId(nil)

                pasteboardClient.clearContents()

                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                _ = pasteboardClient.writeObjects(urls as [NSURL])
                entryFileOpsClient.postFileSystemChanged([])

                return .none

            case .lifecycle(.loadClipboardState):
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                return .send(.lifecycle(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation)))

            case .lifecycle(.appDidBecomeActive):
                let now = Date()
                let monitor = EntryViewLayoutCutClearMonitor()
                let decision = monitor.evaluateOnAppDidBecomeActive(
                    clipboardOperation: state.clipboardOperation,
                    clipboardItems: state.clipboardItems,
                    session: state.cutClearSession,
                    makeSession: { now, sourcePaths in
                        guard !sourcePaths.isEmpty else {
                            return nil
                        }

                        let existingSessionId = entryFileOpsClient.loadClipboardCutSessionId()
                        let sessionId = existingSessionId ?? uuid().uuidString
                        if existingSessionId == nil {
                            entryFileOpsClient.saveClipboardCutSessionId(sessionId)
                        }

                        let heuristic = EntryViewLayoutCutClearHeuristic()
                        return heuristic.makeInitialSession(
                            cutSessionId: sessionId,
                            pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                            sourcePaths: sourcePaths,
                            now: now,
                        )
                    },
                    context: .init(
                        now: now,
                        readPasteboardChangeCount: entryFileOpsClient.clipboardChangeCount,
                        readPasteboardCutSessionId: entryFileOpsClient.loadClipboardCutSessionId,
                        fileExists: entryFileOpsClient.fileExists,
                    ),
                )

                switch decision {
                case .noop:
                    return .none
                case let .keep(updatedSession):
                    state.cutClearSession = updatedSession
                    return .none
                case .clear:
                    return .send(.clipboard(.setClipboardOperation(operation: .copy)))
                }

            case let .clipboard(.copyAbsolutePaths(paths)):
                guard !paths.isEmpty else { return .none }

                let text = paths.joined(separator: "\n")
                pasteboardClient.clearContents()
                _ = pasteboardClient.setString(text, .string)

                return .none

            case let .clipboard(.copyURLs(paths)):
                guard !paths.isEmpty else { return .none }

                let text = paths
                    .map { URL(fileURLWithPath: $0).absoluteString }
                    .joined(separator: "\n")
                pasteboardClient.clearContents()
                _ = pasteboardClient.setString(text, .string)

                return .none

            case let .clipboard(.setClipboardOperation(operation)):
                state.clipboardOperation = operation
                let operationValue = operation == .cut ? "cut" : "copy"
                _ = pasteboardClient.setString(
                    operationValue,
                    NSPasteboard.PasteboardType("fm.voyager.clipboard.operation"),
                )

                if operation == .cut {
                    guard !state.clipboardItems.isEmpty else {
                        state.cutClearSession = nil
                        entryFileOpsClient.saveClipboardCutSessionId(nil)
                        return .none
                    }

                    let cutSessionId = uuid().uuidString
                    entryFileOpsClient.saveClipboardCutSessionId(cutSessionId)
                    let heuristic = EntryViewLayoutCutClearHeuristic()
                    state.cutClearSession = heuristic.makeInitialSession(
                        cutSessionId: cutSessionId,
                        pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                        sourcePaths: state.clipboardItems,
                        now: Date(),
                    )
                } else {
                    state.cutClearSession = nil
                    entryFileOpsClient.saveClipboardCutSessionId(nil)
                }

                return .none

            case let .lifecycle(.syncClipboardState(paths, operation)):
                state.clipboardItems = paths
                state.clipboardOperation = operation

                guard operation == .cut, !paths.isEmpty else {
                    state.cutClearSession = nil
                    return .none
                }

                let existingSessionId = entryFileOpsClient.loadClipboardCutSessionId()
                let sessionId = existingSessionId ?? uuid().uuidString
                if existingSessionId == nil {
                    entryFileOpsClient.saveClipboardCutSessionId(sessionId)
                }

                let heuristic = EntryViewLayoutCutClearHeuristic()
                state.cutClearSession = heuristic.makeInitialSession(
                    cutSessionId: sessionId,
                    pasteboardChangeCount: entryFileOpsClient.clipboardChangeCount(),
                    sourcePaths: paths,
                    now: Date(),
                )
                return .none

            case let .clipboard(.pasteItemsFromClipboard(destinationPath)):
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                guard !clipboardPaths.isEmpty else {
                    return .none
                }

                let operationKind: OperationKind = clipboardOperation == .cut ? .pasteFileMove : .pasteFileCopy

                return .concatenate(
                    .send(.lifecycle(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation))),
                    .send(.clipboard(.pasteItems(
                        sourcePaths: clipboardPaths,
                        destinationPath: destinationPath,
                        operation: clipboardOperation,
                        operationKind: operationKind,
                    ))),
                )

            case let .clipboard(.pasteItems(sourcePaths, destinationPath, operation, operationKind)):
                let destinationURL = URL(fileURLWithPath: destinationPath)
                let destinations = EntryOperationsExecutionSupport.avoidNameCollisions(
                    sourcePaths: sourcePaths,
                    destinationURL: destinationURL,
                    operation: operation,
                    entryFileOpsClient: entryFileOpsClient,
                )

                guard !destinations.isEmpty else {
                    if operation == .cut {
                        return .run { send in
                            await send(.lifecycle(.operationFinished(destinationPath, operationKind, .success(()))))
                        }
                    }
                    return .none
                }

                let isCopy = operation == .copy

                return .run { [entryFileOpsClient, alertClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for (sourceURL, destURL) in destinations {
                        let sourcePath = sourceURL.path
                        let kind: OperationKind = operationKind

                        await send(.lifecycle(.operationStarted(sourcePath, kind)))

                        do {
                            if isCopy {
                                try await entryFileOpsClient.pasteFile(sourceURL, destURL)
                            } else {
                                try await entryFileOpsClient.moveFile(sourceURL, destURL)
                            }
                            await send(.lifecycle(.pathsMutated([sourcePath, destURL.path])))
                            targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                            await send(.lifecycle(.operationFinished(sourcePath, kind, .success(()))))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.lifecycle(.operationFinished(sourcePath, kind, .failure(error))))
                                continue
                            }

                            let replaceResponse = await alertClient.showReplaceAlert(itemName, .move)
                            let shouldReplace = switch replaceResponse {
                            case .replace:
                                true
                            case .stop:
                                false
                            }

                            if shouldReplace {
                                do {
                                    try await entryFileOpsClient.deleteImmediately(destURL)
                                    if isCopy {
                                        try await entryFileOpsClient.pasteFile(sourceURL, destURL)
                                    } else {
                                        try await entryFileOpsClient.moveFile(sourceURL, destURL)
                                    }

                                    await send(.lifecycle(.pathsMutated([sourcePath, destURL.path])))
                                    let destinationFolder = destURL.deletingLastPathComponent().path
                                    targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                                    await send(.lifecycle(.operationFinished(destinationFolder, kind, .success(()))))
                                } catch {
                                    await send(.lifecycle(.operationFinished(
                                        sourcePath,
                                        kind,
                                        .failure(error.fileOpError),
                                    )))
                                }
                            } else {
                                await send(.lifecycle(.operationFinished(sourcePath, kind, .failure(.cancelled))))
                            }
                        } catch {
                            await send(.lifecycle(.operationFinished(sourcePath, kind, .failure(error.fileOpError))))
                        }
                    }

                    if !targets.isEmpty, operationKind.isUndoable {
                        let record = EntryActionRecord(operationKind: operationKind, targets: targets)
                        await send(.lifecycle(.entryActionCompleted(record)))
                    }
                }

            default:
                return .none
            }
        }
    }
}

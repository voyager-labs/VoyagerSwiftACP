import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

public struct EntryClipboardOperationsCutClearMonitor: Sendable {
    public var heuristic: EntryOperationsCutClearHeuristic

    public struct RuntimeContext: Sendable {
        public var now: Date
        public var readPasteboardChangeCount: @Sendable () -> Int
        public var readPasteboardCutSessionId: @Sendable () -> String?
        public var fileExists: @Sendable (String) -> Bool

        public init(
            now: Date,
            readPasteboardChangeCount: @Sendable @escaping () -> Int,
            readPasteboardCutSessionId: @Sendable @escaping () -> String?,
            fileExists: @Sendable @escaping (String) -> Bool,
        ) {
            self.now = now
            self.readPasteboardChangeCount = readPasteboardChangeCount
            self.readPasteboardCutSessionId = readPasteboardCutSessionId
            self.fileExists = fileExists
        }
    }

    public enum Decision: Equatable, Sendable {
        case noop
        case keep(EntryOperationsCutClearHeuristic.CutSession)
        case clear
    }

    public init(heuristic: EntryOperationsCutClearHeuristic = .init()) {
        self.heuristic = heuristic
    }

    public func evaluateOnAppDidBecomeActive(
        clipboardOperation: ClipboardOperation,
        clipboardItems: [String],
        session: EntryOperationsCutClearHeuristic.CutSession?,
        makeSession: (_ now: Date, _ sourcePaths: [String]) -> EntryOperationsCutClearHeuristic.CutSession?,
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
                let monitor = EntryClipboardOperationsCutClearMonitor()
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

                        let heuristic = EntryOperationsCutClearHeuristic()
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
                    let heuristic = EntryOperationsCutClearHeuristic()
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

                let heuristic = EntryOperationsCutClearHeuristic()
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
                var effect = pasteItemsEffect(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                    mutationImpactDestinationPath: nil,
                )
                // 외부 drop placement(.externalObjectImportItem) 복사는 세션별 CancelID로
                // 등록해 resetForDuplicate가 진행 중 복사를 취소할 수 있게 한다. staging이
                // 정리된 뒤에도 복사가 계속되면 불필요한 실패/완료 액션이 유입된다.
                if operationKind == .externalObjectImportItem,
                   let sessionID = state.externalDropImportPlacement?.sessionID
                {
                    effect = effect.cancellable(id: CancelID.externalDrop(sessionID))
                }
                return effect

            case let .clipboard(.performDrop(sourcePaths, destinationPath, isOptionDrag)):
                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                let operationKind: OperationKind = operation == .copy ? .pasteFileCopy : .pasteFileMove
                return pasteItemsEffect(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation,
                    operationKind: operationKind,
                    mutationImpactDestinationPath: destinationPath,
                )

            default:
                return .none
            }
        }
    }

    private func pasteItemsEffect(
        sourcePaths: [String],
        destinationPath: String,
        operation: ClipboardOperation,
        operationKind: OperationKind,
        mutationImpactDestinationPath: String?,
    ) -> Effect<Action> {
        let destinations = EntryClipboardOperationsSupport.avoidNameCollisions(
            sourcePaths: sourcePaths,
            destinationURL: URL(fileURLWithPath: destinationPath),
            operation: operation,
            entryFileOpsClient: entryFileOpsClient,
        )
        guard !destinations.isEmpty else {
            return operation == .cut
                ? .send(.lifecycle(.operationFinished(destinationPath, operationKind, .success(()))))
                : .none
        }

        let executor = EntryClipboardOperationsSupport.PasteExecutor(
            entryFileOpsClient: entryFileOpsClient,
            alertClient: alertClient,
            mutationImpactDestinationPath: mutationImpactDestinationPath,
        )
        return .run { send in
            var targets: [EntryActionRecord.Target] = []
            for (sourceURL, destinationURL) in destinations {
                await send(.lifecycle(.operationStarted(sourceURL.path, operationKind)))
                if let target = await executor.execute(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    isCopy: operation == .copy,
                    operationKind: operationKind,
                    send: send,
                ) {
                    targets.append(target)
                }
            }
            await executor.finishBatch(targets, operationKind: operationKind, send: send)
        }
    }
}

private enum EntryClipboardOperationsSupport {
    struct PasteExecutor {
        let entryFileOpsClient: EntryFileOpsClient
        let alertClient: EntryOperationsAlertClient
        let mutationImpactDestinationPath: String?

        func execute(
            sourceURL: URL,
            destinationURL: URL,
            isCopy: Bool,
            operationKind: OperationKind,
            send: Send<EntryOperationsAction>,
        ) async -> EntryActionRecord.Target? {
            let context = OperationContext(isCopy: isCopy, operationKind: operationKind)
            do {
                try await mutate(sourceURL: sourceURL, destinationURL: destinationURL, isCopy: isCopy)
                return await finishSuccess(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: .init(
                        finishPath: sourceURL.path,
                        operationKind: operationKind,
                        repeatsPathsMutation: true,
                    ),
                    send: send,
                )
            } catch let error as FileOpError where error.isFileExists {
                return await replaceExistingItem(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: context,
                    error: error,
                    send: send,
                )
            } catch {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: operationKind,
                    result: .failure(error.fileOpError),
                ))
                return nil
            }
        }

        func finishBatch(
            _ targets: [EntryActionRecord.Target],
            operationKind: OperationKind,
            send: Send<EntryOperationsAction>,
        ) async {
            guard !targets.isEmpty else { return }
            if operationKind.isUndoable {
                let record = EntryActionRecord(operationKind: operationKind, targets: targets)
                await send(.lifecycle(.entryActionCompleted(record)))
            }
            guard let mutationImpactDestinationPath else { return }
            let impact = EntryOperationsMutationImpact(
                sourceParentPaths: EntryClipboardOperationsSupport.uniqueSourceParentPaths(from: targets),
                destinationPath: mutationImpactDestinationPath,
            )
            await send(.outcome(.entriesMutated(impact)))
        }

        private func replaceExistingItem(
            sourceURL: URL,
            destinationURL: URL,
            context: OperationContext,
            error: FileOpError,
            send: Send<EntryOperationsAction>,
        ) async -> EntryActionRecord.Target? {
            guard let itemName = error.itemName else {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(error),
                ))
                return nil
            }
            guard await alertClient.showReplaceAlert(itemName, .move) == .replace else {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(.cancelled),
                ))
                return nil
            }
            do {
                try await entryFileOpsClient.deleteImmediately(destinationURL)
                try await mutate(sourceURL: sourceURL, destinationURL: destinationURL, isCopy: context.isCopy)
                return await finishSuccess(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    context: .init(
                        finishPath: sourceURL.path,
                        operationKind: context.operationKind,
                        repeatsPathsMutation: false,
                    ),
                    send: send,
                )
            } catch {
                await send(completionAction(
                    sourceURL.path,
                    operationKind: context.operationKind,
                    result: .failure(error.fileOpError),
                ))
                return nil
            }
        }

        private func completionAction(
            _ path: String,
            operationKind: OperationKind,
            result: Result<Void, FileOpError>,
        ) -> EntryOperationsAction {
            if mutationImpactDestinationPath == nil {
                return .lifecycle(.operationFinished(path, operationKind, result))
            }
            return .lifecycle(.dropOperationFinished(path, operationKind, result))
        }

        private func mutate(sourceURL: URL, destinationURL: URL, isCopy: Bool) async throws {
            if isCopy {
                try await entryFileOpsClient.pasteFile(sourceURL, destinationURL)
            } else {
                try await entryFileOpsClient.moveFile(sourceURL, destinationURL)
            }
        }

        private func finishSuccess(
            sourceURL: URL,
            destinationURL: URL,
            context: SuccessContext,
            send: Send<EntryOperationsAction>,
        ) async -> EntryActionRecord.Target {
            let mutatedPaths = [sourceURL.path, destinationURL.path]
            await send(.lifecycle(.pathsMutated(mutatedPaths)))
            if mutationImpactDestinationPath == nil {
                entryFileOpsClient.postFileSystemChanged([
                    sourceURL.deletingLastPathComponent().path,
                    destinationURL.deletingLastPathComponent().path,
                ])
            }
            if context.repeatsPathsMutation {
                await send(.lifecycle(.pathsMutated(mutatedPaths)))
            }
            await send(completionAction(
                context.finishPath,
                operationKind: context.operationKind,
                result: .success(()),
            ))
            return .init(beforePath: sourceURL.path, afterPath: destinationURL.path)
        }
    }

    private struct OperationContext {
        let isCopy: Bool
        let operationKind: OperationKind
    }

    private struct SuccessContext {
        let finishPath: String
        let operationKind: OperationKind
        let repeatsPathsMutation: Bool
    }

    static func uniqueSourceParentPaths(from targets: [EntryActionRecord.Target]) -> [String] {
        var result: [String] = []

        for target in targets {
            guard let sourcePath = target.beforePath else { continue }
            let parentPath = URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
            if !result.contains(where: { EntryDropPathPolicy.areEquivalent($0, parentPath) }) {
                result.append(parentPath)
            }
        }

        return result
    }

    static func avoidNameCollisions(
        sourcePaths: [String],
        destinationURL: URL,
        operation: ClipboardOperation,
        entryFileOpsClient: EntryFileOpsClient,
    ) -> [(URL, URL)] {
        var destinations: [(URL, URL)] = []
        var reservedNameKeys: Set<String> = []
        let volumeSupportsCaseSensitiveNames = (try? destinationURL.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey],
        ))?.volumeSupportsCaseSensitiveNames ?? false

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let fileName = sourceURL.lastPathComponent
            let sourceParent = sourceURL.deletingLastPathComponent()

            if operation == .cut, sourceParent == destinationURL {
                continue
            }

            var destURL = destinationURL.appendingPathComponent(fileName)
            let collisionInBatch = reservedNameKeys.contains(destinationNameKey(
                destURL.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            if collisionInBatch
                || (operation == .copy
                    && sourceParent == destinationURL
                    && entryFileOpsClient.fileExists(destURL.path))
            {
                destURL = nextAvailableDestinationURL(
                    baseName: fileName,
                    destinationURL: destinationURL,
                    reservedNameKeys: reservedNameKeys,
                    volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
                    entryFileOpsClient: entryFileOpsClient,
                )
            }

            reservedNameKeys.insert(destinationNameKey(
                destURL.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            destinations.append((sourceURL, destURL))
        }

        return destinations
    }

    private static func nextAvailableDestinationURL(
        baseName: String,
        destinationURL: URL,
        reservedNameKeys: Set<String>,
        volumeSupportsCaseSensitiveNames: Bool,
        entryFileOpsClient: EntryFileOpsClient,
    ) -> URL {
        let nameWithoutExtension = URL(fileURLWithPath: baseName)
            .deletingPathExtension()
            .lastPathComponent
        let fileExtension = URL(fileURLWithPath: baseName).pathExtension
        var counter = 1
        while true {
            let name: String = if counter == 1 {
                fileExtension.isEmpty
                    ? "\(nameWithoutExtension) copy"
                    : "\(nameWithoutExtension) copy.\(fileExtension)"
            } else {
                fileExtension.isEmpty
                    ? "\(nameWithoutExtension) copy \(counter)"
                    : "\(nameWithoutExtension) copy \(counter).\(fileExtension)"
            }
            let candidate = destinationURL.appendingPathComponent(name)
            let reserved = reservedNameKeys.contains(destinationNameKey(
                candidate.lastPathComponent,
                volumeSupportsCaseSensitiveNames: volumeSupportsCaseSensitiveNames,
            ))
            let filesystemCollision = entryFileOpsClient.fileExists(candidate.path)
            if !reserved, !filesystemCollision {
                return candidate
            }
            counter += 1
        }
    }

    private static func destinationNameKey(
        _ name: String,
        volumeSupportsCaseSensitiveNames: Bool,
    ) -> String {
        let casedName = volumeSupportsCaseSensitiveNames
            ? name
            : name.folding(options: [.caseInsensitive], locale: nil)
        return casedName.precomposedStringWithCanonicalMapping
    }
}

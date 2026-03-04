import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct EntryClipboardOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .copySelectedItems(files):
                state.clipboardItems = files.map(\.fullPath)
                state.clipboardOperation = .copy

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()

                let urls = files.map { URL(fileURLWithPath: $0.fullPath) }
                pasteboard.writeObjects(urls as [NSURL])
                entryFileOpsClient.postFileSystemChanged([])

                return .none

            case .loadClipboardState:
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                return .send(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation))

            case let .copyAbsolutePaths(paths):
                guard !paths.isEmpty else { return .none }

                let text = paths.joined(separator: "\n")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                return .none

            case let .copyURLs(paths):
                guard !paths.isEmpty else { return .none }

                let text = paths
                    .map { URL(fileURLWithPath: $0).absoluteString }
                    .joined(separator: "\n")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                return .none

            case let .setClipboardOperation(operation):
                state.clipboardOperation = operation
                let pasteboard = NSPasteboard.general
                let operationValue = operation == .cut ? "cut" : "copy"
                pasteboard.setString(
                    operationValue,
                    forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"),
                )

                return .none

            case let .syncClipboardState(paths, operation):
                state.clipboardItems = paths
                state.clipboardOperation = operation
                return .none

            case let .pasteItemsFromClipboard(destinationPath):
                let (clipboardPaths, clipboardOperation) = entryFileOpsClient.loadClipboardPaths()
                guard !clipboardPaths.isEmpty else {
                    return .none
                }

                let operationKind: OperationKind = clipboardOperation == .cut ? .pasteFileMove : .pasteFileCopy

                return .concatenate(
                    .send(.syncClipboardState(paths: clipboardPaths, operation: clipboardOperation)),
                    .send(.pasteItems(
                        sourcePaths: clipboardPaths,
                        destinationPath: destinationPath,
                        operation: clipboardOperation,
                        operationKind: operationKind,
                    )),
                )

            case let .pasteItems(sourcePaths, destinationPath, operation, operationKind):
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
                            await send(.operationFinished(destinationPath, operationKind, .success(())))
                        }
                    }
                    return .none
                }

                let isCopy = operation == .copy

                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for (sourceURL, destURL) in destinations {
                        let sourcePath = sourceURL.path
                        let kind: OperationKind = operationKind

                        await send(.operationStarted(sourcePath, kind))

                        do {
                            if isCopy {
                                try await entryFileOpsClient.pasteFile(sourceURL, destURL)
                            } else {
                                try await entryFileOpsClient.moveFile(sourceURL, destURL)
                            }
                            targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                            await send(.operationFinished(sourcePath, kind, .success(())))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(sourcePath, kind, .failure(error)))
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

                                    let destinationFolder = destURL.deletingLastPathComponent().path
                                    targets.append(.init(beforePath: sourcePath, afterPath: destURL.path))
                                    await send(.operationFinished(destinationFolder, kind, .success(())))
                                } catch {
                                    await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                                }
                            } else {
                                await send(.operationFinished(sourcePath, kind, .failure(.cancelled)))
                            }
                        } catch {
                            await send(.operationFinished(sourcePath, kind, .failure(error.fileOpError)))
                        }
                    }

                    if !targets.isEmpty, operationKind.isUndoable {
                        let record = EntryActionRecord(operationKind: operationKind, targets: targets)
                        await send(.entryActionCompleted(record))
                    }
                }

            default:
                return .none
            }
        }
    }
}

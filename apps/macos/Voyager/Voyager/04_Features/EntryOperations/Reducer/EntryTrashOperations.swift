import ComposableArchitecture
import Foundation

@Reducer
struct EntryTrashOperationsReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.trashMetadataStoreClient)
    var trashMetadataStoreClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .moveToTrash(paths):
                return EntryOperationsExecutionSupport.runParallelWithTargets(
                    paths: paths,
                    kind: .moveToTrash,
                    operationKind: .moveToTrash,
                ) { url in
                    let trashURL = try await entryFileOpsClient.moveToTrashAndReturnURL(url)
                    let result: NSURL? = trashURL as NSURL

                    if let trashURL = result as URL? {
                        let metadata = TrashMetadata(
                            trashPath: trashURL.path,
                            originalPath: url.path,
                            deletedDate: Date(),
                        )
                        await trashMetadataStoreClient.save(metadata)
                        return EntryActionRecord.Target(
                            beforePath: url.path,
                            afterPath: trashURL.path,
                        )
                    }
                    return nil
                }

            case let .deleteImmediately(paths):
                guard !paths.isEmpty else {
                    return .none
                }

                let itemNames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }

                return .run { send in
                    let confirmed = await alertClient.showDeleteConfirmationAlert(itemNames)
                    guard confirmed else { return }
                    await send(.deleteImmediatelyConfirmed(paths: paths))
                }

            case let .deleteImmediatelyConfirmed(paths):
                return EntryOperationsExecutionSupport.runParallel(paths: paths, kind: .deleteImmediately) { url in
                    try await entryFileOpsClient.deleteImmediately(url)
                }

            case let .emptyTrash(paths):
                let itemCount = paths.count
                state.pendingEmptyTrashItemCount = itemCount
                state.emptyTrashCompletedCount = 0

                return .run { send in
                    let confirmed = await alertClient.showEmptyTrashConfirmationAlert(itemCount)
                    guard confirmed else {
                        await send(.emptyTrashCancelled)
                        return
                    }
                    await send(.emptyTrashConfirmed(paths: paths))
                }

            case .emptyTrashCancelled:
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case .emptyTrashCompleted:
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case let .emptyTrashConfirmed(paths):
                return EntryOperationsExecutionSupport.runParallel(
                    paths: paths,
                    kind: .deleteImmediately,
                    operation: { url in
                        try await entryFileOpsClient.deleteImmediately(url)
                    },
                    onComplete: {
                        await trashMetadataStoreClient.removeAll()
                    },
                )

            case let .putBackFromTrash(paths):
                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for path in paths {
                        await send(.operationStarted(path, .putBack))

                        guard let metadata = await trashMetadataStoreClient.find(path)
                        else {
                            await send(.operationFinished(
                                path,
                                .putBack,
                                .failure(.system(message: "Original path not found")),
                            ))
                            continue
                        }

                        let originalPath = metadata.originalPath

                        do {
                            try await entryFileOpsClient.putBackFromTrash(
                                URL(fileURLWithPath: path),
                                originalPath,
                            )
                            await send(.operationFinished(path, .putBack, .success(())))
                            targets.append(.init(beforePath: path, afterPath: originalPath))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(path, .putBack, .failure(error)))
                                continue
                            }

                            let replaceResponse = await alertClient.showReplaceAlert(itemName, .putBack)
                            let shouldReplace = switch replaceResponse {
                            case .replace:
                                true
                            case .stop:
                                false
                            }

                            if shouldReplace {
                                do {
                                    let originalURL = URL(fileURLWithPath: originalPath)
                                    try await entryFileOpsClient.deleteImmediately(originalURL)
                                    try await entryFileOpsClient.putBackFromTrash(
                                        URL(fileURLWithPath: path),
                                        originalPath,
                                    )
                                    await send(.operationFinished(path, .putBack, .success(())))
                                    targets.append(.init(beforePath: path, afterPath: originalPath))
                                } catch {
                                    await send(.operationFinished(path, .putBack, .failure(error.fileOpError)))
                                }
                            } else {
                                await send(.operationFinished(path, .putBack, .failure(.cancelled)))
                            }
                        } catch {
                            await send(.operationFinished(path, .putBack, .failure(error.fileOpError)))
                        }
                    }

                    if !targets.isEmpty {
                        let record = EntryActionRecord(operationKind: .putBack, targets: targets)
                        await send(.entryActionCompleted(record))
                    }
                }

            default:
                return .none
            }
        }
    }
}

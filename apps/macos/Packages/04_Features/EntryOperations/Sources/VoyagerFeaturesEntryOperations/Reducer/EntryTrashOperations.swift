import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

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
            case let .trash(.moveToTrash(paths)):
                return EntryOperationsExecutionSupport.runParallelWithTargets(
                    paths: paths,
                    kind: .moveToTrash,
                    operationKind: .moveToTrash,
                ) { [entryFileOpsClient, trashMetadataStoreClient] url in
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

            case let .trash(.deleteImmediately(paths)):
                guard !paths.isEmpty else {
                    return .none
                }

                let itemNames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }

                return .run { send in
                    let confirmed = await alertClient.showDeleteConfirmationAlert(itemNames)
                    guard confirmed else { return }
                    await send(.trash(.deleteImmediatelyConfirmed(paths: paths)))
                }

            case let .trash(.deleteImmediatelyConfirmed(paths)):
                return EntryOperationsExecutionSupport.runParallel(
                    paths: paths,
                    kind: .deleteImmediately,
                    operation: { [entryFileOpsClient] url in
                        try await entryFileOpsClient.deleteImmediately(url)
                    },
                    pathsMutated: { url in [url.path] },
                )

            case let .trash(.emptyTrash(paths)):
                let itemCount = paths.count
                state.pendingEmptyTrashItemCount = itemCount
                state.emptyTrashCompletedCount = 0

                return .run { send in
                    let confirmed = await alertClient.showEmptyTrashConfirmationAlert(itemCount)
                    guard confirmed else {
                        await send(.trash(.emptyTrashCancelled))
                        return
                    }
                    await send(.trash(.emptyTrashConfirmed(paths: paths)))
                }

            case .trash(.emptyTrashCancelled):
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case .lifecycle(.emptyTrashCompleted):
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case let .trash(.emptyTrashConfirmed(paths)):
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

            case let .trash(.putBackFromTrash(paths)):
                return .run { [entryFileOpsClient, trashMetadataStoreClient, alertClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for path in paths {
                        await send(.lifecycle(.operationStarted(path, .putBack)))

                        guard let metadata = await trashMetadataStoreClient.find(path)
                        else {
                            await send(.lifecycle(.operationFinished(
                                path,
                                .putBack,
                                .failure(.system(message: "Original path not found")),
                            )))
                            continue
                        }

                        let originalPath = metadata.originalPath

                        do {
                            try await entryFileOpsClient.putBackFromTrash(
                                URL(fileURLWithPath: path),
                                originalPath,
                            )
                            await trashMetadataStoreClient.remove(path)
                            await send(.lifecycle(.pathsMutated([path, originalPath])))
                            await send(.lifecycle(.operationFinished(path, .putBack, .success(()))))
                            targets.append(.init(beforePath: path, afterPath: originalPath))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.lifecycle(.operationFinished(path, .putBack, .failure(error))))
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
                                    await trashMetadataStoreClient.remove(path)
                                    await send(.lifecycle(.pathsMutated([path, originalPath])))
                                    await send(.lifecycle(.operationFinished(path, .putBack, .success(()))))
                                    targets.append(.init(beforePath: path, afterPath: originalPath))
                                } catch {
                                    await send(.lifecycle(.operationFinished(
                                        path,
                                        .putBack,
                                        .failure(error.fileOpError),
                                    )))
                                }
                            } else {
                                await send(.lifecycle(.operationFinished(path, .putBack, .failure(.cancelled))))
                            }
                        } catch {
                            await send(.lifecycle(.operationFinished(path, .putBack, .failure(error.fileOpError))))
                        }
                    }

                    if !targets.isEmpty {
                        let record = EntryActionRecord(operationKind: .putBack, targets: targets)
                        await send(.lifecycle(.entryActionCompleted(record)))
                    }
                }

            default:
                return .none
            }
        }
    }
}

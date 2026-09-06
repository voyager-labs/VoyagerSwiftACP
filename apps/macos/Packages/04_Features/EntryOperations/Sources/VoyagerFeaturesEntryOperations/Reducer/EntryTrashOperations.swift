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
                    guard confirmed else {
                        await send(.trash(.deleteImmediatelyCancelled))
                        return
                    }
                    await send(.trash(.deleteImmediatelyConfirmed(paths: paths)))
                }

            case .trash(.deleteImmediatelyCancelled):
                return .send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                    operationKind: .deleteImmediately,
                    targets: [],
                    failedCount: 0,
                    cancelledCount: 1,
                    succeededCount: 0,
                    id: UUID(),
                    timestamp: Date(),
                ))))

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
                guard state.loadingContext.coreFinished else {
                    return .none
                }
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
                let cancelledCount = max(1, state.pendingEmptyTrashItemCount)
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .send(.lifecycle(.entryActionCompleted(EntryActionRecord(
                    operationKind: .deleteImmediately,
                    targets: [],
                    failedCount: 0,
                    cancelledCount: cancelledCount,
                    succeededCount: 0,
                    id: UUID(),
                    timestamp: Date(),
                ))))

            case .lifecycle(.emptyTrashCompleted):
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case let .trash(.emptyTrashConfirmed(paths)):
                guard !paths.isEmpty else {
                    return .none
                }

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
                    var failedCount = 0
                    var cancelledCount = 0

                    for path in paths {
                        await send(.lifecycle(.operationStarted(path, .putBack)))

                        guard let metadata = await trashMetadataStoreClient.find(path)
                        else {
                            failedCount += 1
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
                                failedCount += 1
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
                                    failedCount += 1
                                    await send(.lifecycle(.operationFinished(
                                        path,
                                        .putBack,
                                        .failure(error.fileOpError),
                                    )))
                                }
                            } else {
                                cancelledCount += 1
                                await send(.lifecycle(.operationFinished(path, .putBack, .failure(.cancelled))))
                            }
                        } catch {
                            let failure = error.fileOpError
                            if failure == .cancelled {
                                cancelledCount += 1
                            } else {
                                failedCount += 1
                            }
                            await send(.lifecycle(.operationFinished(path, .putBack, .failure(failure))))
                        }
                    }

                    // 전체 실패 배치도 실패 aggregate를 담은 terminal로 마무리한다.
                    let record = EntryActionRecord(
                        operationKind: .putBack,
                        targets: targets,
                        failedCount: failedCount,
                        cancelledCount: cancelledCount,
                        succeededCount: targets.count,
                        id: UUID(),
                        timestamp: Date(),
                    )
                    await send(.lifecycle(.entryActionCompleted(record)))
                }

            default:
                return .none
            }
        }
    }
}

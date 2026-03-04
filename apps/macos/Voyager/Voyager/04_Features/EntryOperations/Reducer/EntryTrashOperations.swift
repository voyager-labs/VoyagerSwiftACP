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

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .moveToTrash(items):
                return EntryOperationsExecutionSupport.runParallelWithTargets(
                    items: items,
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
                        await TrashMetadataStore.shared.save(metadata)
                        return EntryActionRecord.Target(
                            beforePath: url.path,
                            afterPath: trashURL.path,
                        )
                    }
                    return nil
                }

            case let .deleteImmediately(items):
                guard !items.isEmpty else {
                    return .none
                }

                let itemNames = items.map(\.name)

                return .run { send in
                    let confirmed = await alertClient.showDeleteConfirmationAlert(itemNames)
                    guard confirmed else { return }
                    await send(.deleteImmediatelyConfirmed(items: items))
                }

            case let .deleteImmediatelyConfirmed(items):
                return EntryOperationsExecutionSupport.runParallel(items: items, kind: .deleteImmediately) { url in
                    try await entryFileOpsClient.deleteImmediately(url)
                }

            case let .emptyTrash(items):
                let itemCount = items.count
                state.pendingEmptyTrashItemCount = itemCount
                state.emptyTrashCompletedCount = 0

                return .run { send in
                    let confirmed = await alertClient.showEmptyTrashConfirmationAlert(itemCount)
                    guard confirmed else {
                        await send(.emptyTrashCancelled)
                        return
                    }
                    await send(.emptyTrashConfirmed(items: items))
                }

            case .emptyTrashCancelled:
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case .emptyTrashCompleted:
                state.pendingEmptyTrashItemCount = 0
                state.emptyTrashCompletedCount = 0
                return .none

            case let .emptyTrashConfirmed(items):
                return EntryOperationsExecutionSupport.runParallel(
                    items: items,
                    kind: .deleteImmediately,
                    operation: { url in
                        try await entryFileOpsClient.deleteImmediately(url)
                    },
                    onComplete: {
                        await TrashMetadataStore.shared.removeAll()
                    },
                )

            case let .putBackFromTrash(items):
                return .run { [entryFileOpsClient] send in
                    var targets: [EntryActionRecord.Target] = []

                    for item in items {
                        await send(.operationStarted(item.fullPath, .putBack))

                        guard let metadata = await TrashMetadataStore.shared.find(trashPath: item.fullPath)
                        else {
                            await send(.operationFinished(
                                item.fullPath,
                                .putBack,
                                .failure(.system(message: "Original path not found")),
                            ))
                            continue
                        }

                        let originalPath = metadata.originalPath

                        do {
                            try await entryFileOpsClient.putBackFromTrash(
                                URL(fileURLWithPath: item.fullPath),
                                originalPath,
                            )
                            await send(.operationFinished(item.fullPath, .putBack, .success(())))
                            targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                        } catch let error as FileOpError where error.isFileExists {
                            guard let itemName = error.itemName else {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(error)))
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
                                        URL(fileURLWithPath: item.fullPath),
                                        originalPath,
                                    )
                                    await send(.operationFinished(item.fullPath, .putBack, .success(())))
                                    targets.append(.init(beforePath: item.fullPath, afterPath: originalPath))
                                } catch {
                                    await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
                                }
                            } else {
                                await send(.operationFinished(item.fullPath, .putBack, .failure(.cancelled)))
                            }
                        } catch {
                            await send(.operationFinished(item.fullPath, .putBack, .failure(error.fileOpError)))
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

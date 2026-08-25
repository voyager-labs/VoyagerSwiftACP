import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@Reducer
struct EntryOperationsLifecycleReducer {
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryOperationsAlertClient)
    var alertClient
    @Dependency(\.entryOperationSoundClient)
    var soundClient
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient
    @Dependency(\.trashMetadataStoreClient)
    var trashMetadataStoreClient
    @Dependency(\.uuid)
    var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .lifecycle(.windowIDChanged(id)):
                state.windowID = id
                return .none

            case let .lifecycle(.resetForDuplicate(windowID)):
                state.resetForDuplicate(
                    windowID: windowID,
                    loadingCancellationOwnerID: uuid(),
                    undoOwnerID: uuid(),
                )
                return .none

            case .loading(.itemsLoaded):
                return refreshRestorableTrashPaths()

            case let .loading(.streamFinished(generation)):
                guard generation == state.loadingContext.generation,
                      state.loadingContext.streamTerminal
                else {
                    return .none
                }
                return refreshRestorableTrashPaths()

            case let .lifecycle(.restorableTrashPathsLoaded(paths)):
                state.restorableTrashPaths = paths
                return .none

            case let .lifecycle(.syncSelectedEntryIDs(ids)):
                state.selectedEntryIDs = ids
                return .none

            case let .lifecycle(.clearError(filePath)):
                state.itemStates[filePath]?.lastError = nil
                return .none

            case let .lifecycle(.operationStarted(filePath, _)):
                state.itemStates[filePath] = ItemOperationState(isBusy: true, lastError: nil)
                return .none

            case let .lifecycle(.operationFinished(filePath, kind, result)),
                 let .lifecycle(.dropOperationFinished(filePath, kind, result)):
                state.itemStates[filePath]?.isBusy = false

                if case .rename = kind {
                    state.renamingItemId = nil
                    state.renamingText = ""
                }

                switch result {
                case .success:
                    state.itemStates[filePath]?.lastError = nil

                    if case .createFolder = kind {
                        state.renamingItemId = filePath
                        state.renamingText = URL(fileURLWithPath: filePath).lastPathComponent
                    }

                case let .failure(error):
                    state.itemStates[filePath]?.lastError = error
                }

                var effects: [Effect<EntryOperationsAction>] = []

                // Alert effect (existing behavior)
                if case let .failure(error) = result {
                    if case .getInfo = kind {
                        effects.append(.run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        })
                    } else if case .revealInFinder = kind {
                        effects.append(.run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        })
                    }
                }

                if case let .failure(error) = result, error != .cancelled {
                    effects.append(.run { [soundClient] _ in
                        await soundClient.play(.error)
                    })
                }

                return effects.isEmpty ? .none : .merge(effects)

            case let .lifecycle(.pathsMutated(paths)):
                let uniquePaths = Array(Set(paths))
                guard !uniquePaths.isEmpty else { return .none }
                return .run { [entryThumbnailCacheClient] _ in
                    await MainActor.run {
                        entryThumbnailCacheClient.removeThumbnails(for: uniquePaths)
                    }
                }

            case let .lifecycle(.entryActionCompleted(record)):
                switch record.operationKind {
                case .moveToTrash:
                    state.restorableTrashPaths.formUnion(record.targets.compactMap(\.afterPath))
                case .putBack:
                    state.restorableTrashPaths.subtract(record.targets.compactMap(\.beforePath))
                default:
                    break
                }

                switch record.operationKind {
                // 성공 사운드는 성공 semantic target이 있을 때만 재생한다(전체 실패 배치는 무음).
                case .moveToTrash:
                    guard !record.targets.isEmpty else { return .none }
                    return .run { [soundClient] _ in
                        await soundClient.play(.moveToTrash)
                    }
                case .pasteFileCopy, .pasteFileMove, .pasteFileDuplicate, .putBack:
                    guard !record.targets.isEmpty else { return .none }
                    return .run { [soundClient] _ in
                        await soundClient.play(.operationCompleted)
                    }
                default:
                    return .none
                }

            case .lifecycle(.emptyTrashCompleted):
                state.restorableTrashPaths = []
                return .run { [soundClient] _ in
                    await soundClient.play(.emptyTrash)
                }

            default:
                return .none
            }
        }
    }

    private func refreshRestorableTrashPaths() -> Effect<Action> {
        .run { [trashMetadataStoreClient] send in
            let paths = await Set(trashMetadataStoreClient.load().map(\.trashPath))
            await send(.lifecycle(.restorableTrashPathsLoaded(paths)))
        }
    }
}

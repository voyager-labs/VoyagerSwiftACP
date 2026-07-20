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
    @Dependency(\.entryThumbnailCacheClient)
    var entryThumbnailCacheClient
    @Dependency(\.trashMetadataStoreClient)
    var trashMetadataStoreClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .lifecycle(.windowIDChanged(id)):
                state.windowID = id
                return .none

            case let .lifecycle(.resetForDuplicate(windowID)):
                state.resetForDuplicate(windowID: windowID)
                return .none

            case .loading(.itemsLoaded):
                return .run { [trashMetadataStoreClient] send in
                    let paths = await Set(trashMetadataStoreClient.load().map(\.trashPath))
                    await send(.lifecycle(.restorableTrashPathsLoaded(paths)))
                }

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

            case let .lifecycle(.operationFinished(filePath, kind, result)):
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

                    if case .getInfo = kind {
                        return .run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        }
                    }

                    if case .revealInFinder = kind {
                        return .run { [alertClient] _ in
                            await alertClient.showGetInfoFailureAlert(error.message, error.suggestion)
                        }
                    }
                }

                return .none

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
                return .none

            case .lifecycle(.emptyTrashCompleted):
                state.restorableTrashPaths = []
                return .none

            default:
                return .none
            }
        }
    }
}

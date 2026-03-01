import ComposableArchitecture

@Reducer
struct FileManagerContentEntryOperationsFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .entryOperations(entryOperationsAction) = action else {
                return .none
            }

            return handleEntryOperationsAction(entryOperationsAction, state: &state)
        }
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .itemsLoaded,
             .collectionItemsLoadedFromSearch,
             .setCollectionMode:
            state.entryThumbnails.thumbnailRequestsInFlight.removeAll(keepingCapacity: false)
            state.entryThumbnails.thumbnailRenderVersion &+= 1
            entryThumbnailCacheClient.clearCache()
            return .send(.entryArrangements(.reapply))

        case .operationFinished:
            return .merge(
                .send(.entryArrangements(.reapply)),
                reloadEntryItemsEffect(state: state),
            )

        case .emptyTrashCompleted:
            return .send(.closeWindow)

        default:
            return .none
        }
    }

    private func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        switch state.navigation.navigationState {
        case let .folder(path):
            .send(.entryOperations(.loadItems(
                path: path,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .recents:
            .send(.entryOperations(.loadRecentItems(showHidden: state.entryViewLayout.showHiddenFiles)))
        case let .tags(tagName):
            .send(.entryOperations(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .computer:
            .send(.entryOperations(.loadComputerItems))
        case .collection:
            .none
        }
    }
}

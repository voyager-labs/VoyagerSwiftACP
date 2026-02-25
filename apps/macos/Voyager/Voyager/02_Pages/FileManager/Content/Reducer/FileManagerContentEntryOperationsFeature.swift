import ComposableArchitecture

@Reducer
struct FileManagerContentEntryOperationsFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .entryOperations(entryOperationsAction) = action else {
                return .none
            }

            return handleEntryOperationsAction(entryOperationsAction, state: state)
        }
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: State,
    ) -> Effect<Action> {
        switch action {
        case .itemsLoaded,
             .collectionItemsLoadedFromSearch,
             .setCollectionMode:
            .send(.entryArrangements(.reapply))

        case .operationFinished:
            .merge(
                .send(.entryArrangements(.reapply)),
                reloadEntryItemsEffect(state: state),
            )

        case .emptyTrashCompleted:
            .send(.closeWindow)

        default:
            .none
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

import ComposableArchitecture
import VoyagerFeaturesEntryOperations

extension FileManagerContentFeature {
    func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .loading(.itemsLoaded):
            .none

        case let .lifecycle(.entryActionCompleted(record)):
            handleEntryActionCompleted(record, state: state)

        case let .undoRedo(.entryActionApplied(direction: direction, record: record)):
            handleEntryActionApplied(direction: direction, record: record, state: state)

        case let .lifecycle(.pathsMutated(paths)):
            handleMutatedPaths(paths, state: state)

        case .lifecycle(.operationFinished):
            reloadEntryItemsEffect(state: state)

        case .lifecycle(.emptyTrashCompleted):
            .send(.delegate(.closeWindow))

        default:
            .none
        }
    }

    func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
        )
    }

    private func handleEntryActionCompleted(_ record: EntryActionRecord, state: State) -> Effect<Action> {
        guard case .collection = state.navigation.navigationState,
              record.operationKind == .putBack
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.afterPath),
            state: state,
        )
    }

    private func handleEntryActionApplied(
        direction: EntryActionDirection,
        record: EntryActionRecord,
        state: State,
    ) -> Effect<Action> {
        guard case .collection = state.navigation.navigationState,
              direction == .undo,
              record.operationKind == .moveToTrash
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.beforePath),
            state: state,
        )
    }

    private func restoreCollectionPathsEffect(_ restoredPaths: [String], state _: State) -> Effect<Action> {
        guard !restoredPaths.isEmpty else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.addCollectionPaths(restoredPaths))))
    }

    private func handleMutatedPaths(_ paths: [String], state: State) -> Effect<Action> {
        guard case .collection = state.navigation.navigationState else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.removeCollectionPaths(paths))))
    }

    func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(path: path, showHidden: showHidden)))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(showHidden: showHidden)))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(tagName: tagName, showHidden: showHidden)))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection:
            .none
        }
    }
}

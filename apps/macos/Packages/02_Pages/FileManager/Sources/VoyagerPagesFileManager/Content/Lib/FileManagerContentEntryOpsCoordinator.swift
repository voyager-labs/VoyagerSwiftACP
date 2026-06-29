import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

enum FileManagerContentEntryOpsCoordinator {
    static func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case let .loading(.itemsLoaded(entries)):
            handleItemsLoaded(entries: entries, state: &state)

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

    static func reloadEntryItemsEffect(state: FileManagerContentState) -> Effect<FileManagerContentAction> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
        )
    }

    static func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
    ) -> Effect<FileManagerContentAction> {
        switch navigationState {
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(path: path, showHidden: showHidden)))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(showHidden: showHidden)))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: showHidden,
            )))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection:
            .none
        }
    }

    private static func handleEntryActionCompleted(
        _ record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
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

    private static func handleEntryActionApplied(
        direction: EntryActionDirection,
        record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
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

    private static func restoreCollectionPathsEffect(
        _ restoredPaths: [String],
        state _: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard !restoredPaths.isEmpty else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.addCollectionPaths(restoredPaths))))
    }

    private static func handleMutatedPaths(
        _ paths: [String],
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.removeCollectionPaths(paths))))
    }

    /// itemsLoaded 후 pendingSelectEntryID가 있으면 해당 엔트리를 선택 focus
    private static func handleItemsLoaded(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard let selectID = state.pendingSelectEntryID else { return .none }
        state.pendingSelectEntryID = nil
        guard entries.contains(where: { $0.id == selectID }) else { return .none }
        return .send(.entryViewLayout(.internal(.setSelectionState(
            ids: Set([selectID]),
            lastSelectedId: selectID,
            rangeAnchorId: selectID,
            shouldScrollToSelection: true,
        ))))
    }

    private static func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

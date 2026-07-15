import ComposableArchitecture
import Foundation
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

        case .lifecycle(.dropOperationFinished):
            .none

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
        case .home:
            .none
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
        case .collection, .aiChat, .aiChatSessions:
            .none
        }
    }

    /// itemsLoaded reconcile 전에 pending selection을 동기 반영한다.
    @discardableResult
    static func applyPendingSelectionForLoadedEntries(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Bool {
        guard let selectID = state.pendingSelectEntryID else { return false }
        let normalizedSelectID = normalizedPath(selectID)
        guard let matchedID = entries.first(where: { normalizedPath($0.id) == normalizedSelectID })?.id else {
            return false
        }

        let selectedIds = Set([matchedID])
        let didChangeSelection = state.entryViewLayout.selectedIds != selectedIds
        state.pendingSelectEntryID = nil
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedID
        state.entryViewLayout.rangeAnchorId = matchedID
        state.entryViewLayout.shouldScrollToSelection = true
        return didChangeSelection
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
        guard applyPendingSelectionForLoadedEntries(entries: entries, state: &state) else {
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

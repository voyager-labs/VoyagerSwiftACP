import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentLayoutRoutingFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            if let effect = routeSidebarDropAction(action) { return effect }

            guard case let .entryViewLayout(entryViewLayoutAction) = action else {
                return .none
            }

            return routeEntryViewLayoutAction(entryViewLayoutAction)
        }
    }

    private func routeSidebarDropAction(_ action: Action) -> Effect<Action>? {
        switch action {
        case let .dropItemsToSidebarFolder(providers, targetURL):
            .send(.entries(.handleDrop(
                providers: providers,
                destinationPath: targetURL.path,
            )))
        case let .dropItemsToTag(providers, tagName):
            .send(.entries(.handleDropToTag(
                providers: providers,
                tagName: tagName,
            )))
        default:
            nil
        }
    }

    private func routeEntryViewLayoutAction(_ action: EntryViewLayoutAction) -> Effect<Action> {
        if let effect = routeSelectionAction(action) { return effect }
        if let effect = routeDropAction(action) { return effect }
        if let effect = routeRenameAndOpenAction(action) { return effect }

        switch action {
        case .toggleShowHiddenFiles:
            return .send(.entries(.toggleShowHiddenFiles))

        case .setSelectedIds,
             .setSelectedIdsFromLasso,
             .selectNextItem,
             .selectPreviousItem,
             .selectByOffset,
             .setDropTargeted,
             .startDrag,
             .handleDrop,
             .dropItems,
             .startRename,
             .updateRenamingText,
             .commitRename,
             .cancelRename,
             .openSelectedItem,
             .setSelectionState,
             .applySelectAll,
             .applyClearSelection,
             .applySelectionOffset,
             .setRenameState,
             .setShowHiddenFiles,
             .updateGridColumnCount,
             .resetScrollFlag:
            return .none
        }
    }

    private func routeSelectionAction(_ action: EntryViewLayoutAction) -> Effect<Action>? {
        switch action {
        case let .selectNextItem(isShiftPressed):
            .send(.entries(.selectNextItem(isShiftPressed: isShiftPressed)))
        case let .selectPreviousItem(isShiftPressed):
            .send(.entries(.selectPreviousItem(isShiftPressed: isShiftPressed)))
        case let .selectByOffset(offset, isShiftPressed):
            .send(.entries(.selectByOffset(offset: offset, isShiftPressed: isShiftPressed)))
        default:
            nil
        }
    }

    private func routeDropAction(_ action: EntryViewLayoutAction) -> Effect<Action>? {
        switch action {
        case let .startDrag(paths):
            .send(.entries(.startDrag(paths: paths)))
        case let .handleDrop(providers, destinationPath):
            .send(.entries(.handleDrop(providers: providers, destinationPath: destinationPath)))
        case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
            .send(.entries(.dropItems(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                isOptionDrag: isOptionDrag,
            )))
        default:
            nil
        }
    }

    private func routeRenameAndOpenAction(_ action: EntryViewLayoutAction) -> Effect<Action>? {
        switch action {
        case let .startRename(id):
            .send(.entries(.startRename(id: id)))
        case .commitRename:
            .send(.entries(.commitRename))
        case .openSelectedItem:
            .send(.entries(.openSelectedItem))
        default:
            nil
        }
    }
}

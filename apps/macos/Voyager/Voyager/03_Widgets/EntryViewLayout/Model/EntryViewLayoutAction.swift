import AppKit
import ComposableArchitecture
import Foundation

@CasePathable
enum EntryViewLayoutAction: CasePathable, Sendable {
    case setSelectionState(
        ids: Set<String>,
        lastSelectedId: String?,
        rangeAnchorId: String?,
        shouldScrollToSelection: Bool,
    )
    case setSelectedIds(ids: Set<String>, lastSelectedId: String?)
    case setSelectedIdsFromLasso(ids: Set<String>, lastSelectedId: String?)
    case applySelectAll(orderedItemIds: [String])
    case applyClearSelection
    case selectNextItem(isShiftPressed: Bool)
    case selectPreviousItem(isShiftPressed: Bool)
    case selectByOffset(offset: Int, isShiftPressed: Bool)
    case applySelectionOffset(offset: Int, isShiftPressed: Bool, orderedItemIds: [String])
    case updateGridColumnCount(Int)
    case setListVisibleColumns([EntryListColumn])
    case setListColumnVisibility(column: EntryListColumn, isVisible: Bool)
    case moveListColumn(from: Int, to: Int)
    case resetListVisibleColumns
    case resetScrollFlag

    case setDropTargeted(Bool)
    case startDrag(paths: [String])
    case handleDrop(providers: [NSItemProvider], destinationPath: String)
    case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)

    case startRename(id: String)
    case setRenameState(id: String?, text: String)
    case updateRenamingText(String)
    case commitRename
    case cancelRename

    case openSelectedItem
    case setShowHiddenFiles(Bool)
    case toggleShowHiddenFiles
}

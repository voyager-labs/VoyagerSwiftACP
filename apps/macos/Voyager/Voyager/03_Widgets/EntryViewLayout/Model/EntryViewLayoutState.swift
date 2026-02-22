import ComposableArchitecture
import Foundation

@ObservableState
struct EntryViewLayoutState: Equatable {
    var selectedIds: Set<String> = []
    var lastSelectedId: String?
    var rangeAnchorId: String?
    var shouldScrollToSelection: Bool = false
    var gridColumnCount: Int = 1
    var listVisibleColumns: [EntryListColumn] = EntryListColumn.defaultVisibleColumns

    var renamingItemId: String?
    var renamingText: String = ""

    var isDropTargeted: Bool = false
    var showHiddenFiles: Bool = false

    var entries: [EntryModel] = []

    var isRenaming: Bool {
        renamingItemId != nil
    }
}

import Foundation

extension FileManagerContentState {
    var selectedIds: Set<EntryModel.ID> { entryViewLayout.selectedIds }
    var selectedEntries: [EntryModel] { entries.filter { selectedIds.contains($0.id) } }
    var hasSelectableEntriesInLayout: Bool { !selectedEntries.isEmpty }
    var selectedEntryCount: Int { selectedEntries.count }
    var lastSelectedId: EntryModel.ID? { entryViewLayout.lastSelectedId }
    var shouldScrollToSelection: Bool { entryViewLayout.shouldScrollToSelection }
    var gridColumnCount: Int { entryViewLayout.gridColumnCount }
    var listVisibleColumns: [EntryListColumn] { entryViewLayout.listVisibleColumns }
    var isDropTargeted: Bool { entryViewLayout.isDropTargeted }
    var showHiddenFiles: Bool { entryViewLayout.showHiddenFiles }

    var entries: [EntryModel] { entryViewLayout.entries }

    var groupKey: GroupKey { entryViewLayout.entryArrangements.groupKey }
    var groupedItems: [GroupedItems] { entryViewLayout.entryArrangements.groupedItems }
    var collapsedGroups: Set<String> { entryViewLayout.entryArrangements.collapsedGroups }
    var sortKey: SortKey { entryViewLayout.entryArrangements.sortKey }
    var sortOrder: SortOrder { entryViewLayout.entryArrangements.sortOrder }

    var currentPath: String { navigation.currentPath }
    var savedScrollOffset: CGPoint? { navigation.scrollPositions[navigation.currentPath] }

    var clipboardItems: Set<String> { Set(entryViewLayout.entryOperations.clipboardItems) }
    var clipboardOperation: ClipboardOperation { entryViewLayout.entryOperations.clipboardOperation }
    var canPaste: Bool { !entryViewLayout.entryOperations.clipboardItems.isEmpty }
}

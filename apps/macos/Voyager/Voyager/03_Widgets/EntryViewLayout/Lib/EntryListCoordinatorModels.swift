import CoreGraphics
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

struct EntryListCoordinatorRenderSnapshot: Equatable {
    let listVisibleColumns: [EntryListColumn]
    let listIconSize: CGFloat
    let listTextSize: CGFloat
    let entries: [EntryModel]
    let groupKey: GroupKey
    let groupedItems: [GroupedItems]
    let currentPath: String
    let thumbnailRenderVersion: Int
    let selectedIds: Set<EntryModel.ID>
    let clipboardItems: Set<String>
    let clipboardOperation: ClipboardOperation
    let renamingItemId: EntryModel.ID?
    let sortKey: SortKey
    let sortOrder: SortOrder
    let showHiddenFiles: Bool
    let shouldScrollToSelection: Bool
    let isDropTargeted: Bool

    init(state: EntryViewLayoutState) {
        listVisibleColumns = state.listVisibleColumns
        listIconSize = state.listIconSize
        listTextSize = state.listTextSize
        entries = state.entries
        groupKey = state.entryArrangements.groupKey
        groupedItems = state.entryArrangements.groupedItems
        currentPath = state.currentPath
        thumbnailRenderVersion = state.entryThumbnail.renderVersion
        selectedIds = state.selectedIds
        clipboardItems = Set(state.entryOperations.clipboardItems)
        clipboardOperation = state.entryOperations.clipboardOperation
        renamingItemId = state.entryOperations.renamingItemId
        sortKey = state.entryArrangements.sortKey
        sortOrder = state.entryArrangements.sortOrder
        showHiddenFiles = state.showHiddenFiles
        shouldScrollToSelection = state.shouldScrollToSelection
        isDropTargeted = state.isDropTargeted
    }
}

import AppKit

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

struct EntryGridSection {
    let title: String?
    let colorCode: Int?
    let count: Int
    let items: [EntryModel]
    let isCollapsed: Bool
}

struct EntryGridRenderSnapshot: Equatable {
    let entries: [EntryModel]
    let entriesCount: Int
    let groupKey: GroupKey
    let groupedItems: [GroupedItems]
    let collapsedGroups: Set<String>
    let selectedIds: Set<EntryModel.ID>
    let clipboardItems: Set<String>
    let clipboardOperation: ClipboardOperation
    let renamingItemId: EntryModel.ID?
    let gridIconSize: CGFloat
    let gridTextSize: CGFloat
    let showHiddenFiles: Bool
    let shouldScrollToSelection: Bool
    let isDropTargeted: Bool
    let currentPath: String
    let thumbnailRenderVersion: Int

    init(state: EntryViewLayoutState) {
        entries = state.entries
        entriesCount = state.entries.count
        groupKey = state.entryArrangements.groupKey
        groupedItems = state.entryArrangements.groupedItems
        collapsedGroups = state.entryArrangements.collapsedGroups
        selectedIds = state.selectedIds
        clipboardItems = Set(state.entryOperations.clipboardItems)
        clipboardOperation = state.entryOperations.clipboardOperation
        renamingItemId = state.entryOperations.renamingItemId
        gridIconSize = state.gridIconSize
        gridTextSize = state.gridTextSize
        showHiddenFiles = state.showHiddenFiles
        shouldScrollToSelection = state.shouldScrollToSelection
        isDropTargeted = state.isDropTargeted
        currentPath = state.currentPath
        thumbnailRenderVersion = state.entryThumbnail.renderVersion
    }
}

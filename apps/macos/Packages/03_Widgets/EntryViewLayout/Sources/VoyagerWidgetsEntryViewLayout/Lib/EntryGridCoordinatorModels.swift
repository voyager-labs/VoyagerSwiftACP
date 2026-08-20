@preconcurrency import AppKit
import VoyagerEntitiesEntry

struct EntryGridSection {
    let title: String?
    let colorCode: Int?
    let count: Int
    let items: [EntryModel]
    let isCollapsed: Bool
}

struct EntryGridRenderSnapshot: Equatable {
    let presentation: EntryViewLayoutPresentation
    let entries: [EntryModel]
    let entriesCount: Int
    let groupKey: EntryViewLayoutGroupKey
    let collapsedGroups: Set<String>
    let selectedIds: Set<EntryModel.ID>
    let clipboardCutPaths: Set<String>
    let renamingItemId: EntryModel.ID?
    let gridIconSize: CGFloat
    let gridTextSize: CGFloat
    let showHiddenFiles: Bool
    let shouldScrollToSelection: Bool
    let isDropTargeted: Bool
    let currentPath: String
    let outlineProjectionRevision: Int

    init(state: EntryViewLayoutState) {
        presentation = state.presentation
        entries = state.entries
        entriesCount = state.entries.count
        groupKey = .fromShared(state.entryArrangements.groupKey.rawValue)
        collapsedGroups = state.entryArrangements.collapsedGroups
        selectedIds = state.selectedIds
        clipboardCutPaths = state.entryOperations.clipboardOperation == .cut
            ? Set(state.entryOperations.clipboardItems)
            : []
        renamingItemId = state.entryOperations.renamingItemId
        gridIconSize = state.gridIconSize
        gridTextSize = state.gridTextSize
        showHiddenFiles = state.showHiddenFiles
        shouldScrollToSelection = state.shouldScrollToSelection
        isDropTargeted = state.isDropTargeted
        currentPath = state.currentPath
        outlineProjectionRevision = state.outlineProjectionRevision
    }
}

import ComposableArchitecture
import CoreGraphics
import Foundation
import IdentifiedCollections
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerShared

@ObservableState
public struct EntryViewLayoutState: Equatable {
    public enum Mode: String, Equatable, Codable, Sendable {
        case list
        case grid

        public var isGridLayout: Bool {
            self == .grid
        }

        public static func from(_ rawValue: String?) -> Mode? {
            rawValue.flatMap(Self.init(rawValue:))
        }
    }

    public var mode: Mode = .list
    public var isLoading: Bool = false
    public var renamingItemId: EntryModel.ID?
    public var sortKey: EntryViewLayoutSortKey = .name
    public var sortOrder: VoyagerShared.SortOrder = .ascending
    public var groupKey: EntryViewLayoutGroupKey = .none
    public var collapsedGroups: Set<String> = []
    public var presentationSections: [EntryViewLayoutSection] = []
    public var openWithApplications: [ApplicationInfo] = []
    public var clipboardCutPaths: Set<String> = []
    /// FileManagerContentState.entryOperations에서 동기화되는 투영값
    public var restorableTrashPaths: Set<String> = []
    public var trashDirectoryPath: String?
    public var busyEntryPaths: Set<String> = []
    public var hierarchy: EntryListHierarchyState = .init()
    public var outlineProjectionRevision: Int = 0

    /// Cached set of visible selectable entry IDs from the last reconciliation.
    /// Used to detect whether visible entries actually changed, avoiding
    /// unnecessary `outlineProjectionRevision` bumps on selection-only changes.
    var lastVisibleSelectableEntryIDs: Set<EntryModel.ID>?

    public var currentPath: String = ""
    public var selectedIds: Set<EntryModel.ID> = []
    public var lastSelectedId: EntryModel.ID?
    public var rangeAnchorId: EntryModel.ID?
    public var shouldScrollToSelection: Bool = false
    public var gridColumnCount: Int = 1
    public var listVisibleColumns: [EntryListColumn] = EntryListColumn.defaultVisibleColumns

    public var isDropTargeted: Bool = false
    public var showHiddenFiles: Bool = false
    public var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    public var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    public var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    public var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize
    public var savedScrollOffset: CGPoint?

    /// Items sourced from collection search results.
    public var collectionItems: IdentifiedArrayOf<EntryModel> = []

    /// Indicates a collection file is being opened before snapshot/search results are applied.
    public var isCollectionContentLoading = false

    /// Replacement streams are accepted only when their epoch matches this value.
    public var collectionReplaceEpoch = 0
    public var activeCollectionReplacePaths: [String] = []
    public var expectedCollectionReplaceBatchIndex = 0
    public var activeCollectionAppendExpectedBatchIndices: [Int: Int] = [:]
    public var activeCollectionAppendPaths: [Int: [String]] = [:]
    public var finishedCollectionAppendTokens: Set<Int> = []
    public var nextCollectionAppendToken = 0
    public var collectionCoreFinished = false
    public var collectionStreamCompleted = false
    public var collectionIncompleteFailure: String?
    public var removedCollectionPaths: Set<String> = []

    /// When true, `displayItems` returns `collectionItems`; otherwise `entries`.
    public var isCollectionMode: Bool = false

    /// Canonical display items: `collectionItems` in collection mode, `entries` otherwise.
    public var displayItems: IdentifiedArrayOf<EntryModel> {
        isCollectionMode ? collectionItems : IdentifiedArrayOf(uniqueElements: entries)
    }

    /// Ordered snapshot of `displayItems` for list/grid rendering.
    public var displayOrderItems: [EntryModel] {
        Array(displayItems)
    }

    public var presentation: EntryViewLayoutPresentation {
        EntryViewLayoutPresentation(
            sections: presentationSections.isEmpty
                ? [.ungrouped(items: entries)]
                : presentationSections,
            selectedIds: selectedIds,
            openWithApplications: openWithApplications,
        )
    }

    public var entries: [EntryModel] = []

    public func visibleSelectableEntryIDs(isNormalDirectoryPage: Bool) -> [EntryModel.ID] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntryIDs
    }

    public func visibleSelectableEntries(isNormalDirectoryPage: Bool) -> [EntryModel] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntries
    }

    mutating func synchronizeEntries(_ entries: [EntryModel]) {
        self.entries = entries
        presentationSections = [.ungrouped(items: entries)]
        reconcileSelectionWithVisibleEntries()
    }

    mutating func synchronizePresentation(
        entries: [EntryModel],
        sections: [EntryViewLayoutSection],
        openWithApplications: [ApplicationInfo],
    ) {
        self.entries = entries
        presentationSections = sections.isEmpty ? [.ungrouped(items: entries)] : sections
        self.openWithApplications = openWithApplications
        reconcileSelectionWithVisibleEntries()
    }

    public var hierarchyProjectionIsActive: Bool {
        mode == .list
            && !isCollectionMode
            && !hierarchy.rootPath.isEmpty
            && groupKey == .none
    }

    func contextMenuSelectedEntries(rowEntry: EntryModel?) -> [EntryModel] {
        guard !selectedIds.isEmpty else {
            return rowEntry.map { [$0] } ?? []
        }
        let selectableEntries = hierarchyProjectionIsActive
            ? visibleSelectableEntries(isNormalDirectoryPage: true)
            : entries
        return selectableEntries.filter { selectedIds.contains($0.id) }
    }

    private func outlineProjection(isNormalDirectoryPage: Bool) -> EntryListOutlineProjection {
        EntryListOutlineProjection(
            revision: outlineProjectionRevision,
            rootEntries: entries,
            hierarchyState: hierarchy,
            context: .init(
                mode: mode,
                isNormalDirectoryPage: isNormalDirectoryPage && !isCollectionMode,
                hasActiveGrouping: groupKey != .none,
            ),
            sortKey: sortKey.sharedSortKey,
            sortOrder: sortOrder,
        )
    }

    var selectionProjectionIsHierarchyEnabled: Bool {
        !hierarchy.rootPath.isEmpty
    }

    mutating func advanceOutlineProjectionRevision() {
        outlineProjectionRevision &+= 1
    }

    mutating func reconcileSelectionWithVisibleEntries() {
        let previousSelectedIds = selectedIds
        let remainingIds = Set(visibleSelectableEntryIDs(
            isNormalDirectoryPage: selectionProjectionIsHierarchyEnabled,
        ))
        selectedIds = selectedIds.intersection(remainingIds)

        if remainingIds != lastVisibleSelectableEntryIDs {
            advanceOutlineProjectionRevision()
            lastVisibleSelectableEntryIDs = remainingIds
        }

        guard !selectedIds.isEmpty else {
            lastSelectedId = nil
            rangeAnchorId = nil
            shouldScrollToSelection = false
            return
        }

        if lastSelectedId.map(selectedIds.contains) != true {
            let visibleIDs = visibleSelectableEntryIDs(
                isNormalDirectoryPage: selectionProjectionIsHierarchyEnabled,
            )
            lastSelectedId = visibleIDs.first { selectedIds.contains($0) }
        }
        if rangeAnchorId.map(selectedIds.contains) != true {
            rangeAnchorId = lastSelectedId
        }
        if selectedIds != previousSelectedIds {
            shouldScrollToSelection = false
        }
    }

    public init() {}

    public mutating func clearCollectionPresentation() {
        collectionReplaceEpoch &+= 1
        isCollectionMode = false
        collectionItems = []
        isCollectionContentLoading = false
        activeCollectionReplacePaths = []
        expectedCollectionReplaceBatchIndex = 0
        activeCollectionAppendExpectedBatchIndices = [:]
        activeCollectionAppendPaths = [:]
        finishedCollectionAppendTokens = []
        collectionCoreFinished = false
        collectionStreamCompleted = false
        collectionIncompleteFailure = nil
        removedCollectionPaths = []
        entries = displayOrderItems

        let remainingIDs = Set(entries.map(\.id))
        selectedIds = selectedIds.intersection(remainingIDs)
        guard !selectedIds.isEmpty else {
            lastSelectedId = nil
            rangeAnchorId = nil
            shouldScrollToSelection = false
            return
        }

        if lastSelectedId.map(selectedIds.contains) != true {
            lastSelectedId = entries.first { selectedIds.contains($0.id) }?.id
        }
        if rangeAnchorId.map(selectedIds.contains) != true {
            rangeAnchorId = lastSelectedId
        }
        shouldScrollToSelection = false
    }
}

import ComposableArchitecture
import CoreGraphics
import Foundation
import IdentifiedCollections
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
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
    public var entryOperations: EntryOperationsFeature.State = .init()
    public var entryThumbnail: EntryThumbnailFeature.State = .init()
    public var entryArrangements: EntryArrangementsFeature.State = .init()
    public var hierarchy: EntryListHierarchyState = .init()
    public var outlineProjectionRevision: Int = 0
    public var trashDirectoryPath: String?

    /// Cached set of visible selectable entry IDs from the last reconciliation.
    /// Used to detect whether visible entries actually changed, avoiding
    /// unnecessary `outlineProjectionRevision` bumps on selection-only changes.
    var lastVisibleSelectableEntryIDs: Set<EntryModel.ID>?
    var lastReconciledOutlineProjection: EntryListOutlineProjection?

    public var currentPath: String = ""
    public var selectedIds: Set<EntryModel.ID> = []
    public var lastSelectedId: EntryModel.ID?
    public var rangeAnchorId: EntryModel.ID?
    public var shouldScrollToSelection: Bool = false
    /// 타자 검색 등에서 일회성으로 스크롤할 대상 entry id. entries 동기화나 collection 정리 시 소모된다.
    public var pendingTypeScrollTargetId: EntryModel.ID?
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
    public var collectionWindowID: UUID?
    public var collectionLoadingCancellationOwnerID = UUID()

    /// Indicates a collection file is being opened before snapshot/search results are applied.
    public var isCollectionContentLoading = false

    /// Replacement streams are accepted only when their epoch matches this value.
    public var collectionReplaceEpoch = 0
    public var activeCollectionReplacePaths: [String] = []
    public var expectedCollectionReplaceBatchIndex = 0
    public var activeAppendExpectedBatchIndices: [Int: Int] = [:]
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
        isCollectionMode ? collectionItems : entryOperations.items
    }

    /// Ordered snapshot of `displayItems` for list/grid rendering.
    public var displayOrderItems: [EntryModel] {
        Array(displayItems)
    }

    public var presentation: EntryViewLayoutPresentation {
        EntryViewLayoutPresentation(
            sections: entryArrangements.groupedItems.isEmpty
                ? [.ungrouped(items: entries)]
                : entryArrangements.groupedItems.enumerated().map { index, group in
                    // 빈 groupName은 groupKey .none(ungrouped)을 뜻하므로 group header 없이 flat 렌더링한다.
                    EntryViewLayoutSection(
                        id: group.groupName.isEmpty ? "group-\(index)" : group.groupName,
                        title: group.groupName.isEmpty ? nil : group.groupName,
                        colorCode: group.colorCode,
                        items: group.items,
                        isCollapsed: entryArrangements.collapsedGroups.contains(group.groupName),
                    )
                },
            selectedIds: selectedIds,
            openWithApplications: entryOperations.commonApplicationsForSelectedFiles,
        )
    }

    public var entries: [EntryModel] = []

    public func visibleSelectableEntryIDs(isNormalDirectoryPage: Bool) -> [EntryModel.ID] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntryIDs
    }

    public func visibleSelectableEntries(isNormalDirectoryPage: Bool) -> [EntryModel] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntries
    }

    /// 현재 상태 기준 outline projection을 반환한다.
    /// 테스트에서 reconcile 후 lastReconciledOutlineProjection 기대값을 생성할 때 사용한다.
    func currentOutlineProjection() -> EntryListOutlineProjection {
        outlineProjection(isNormalDirectoryPage: selectionProjectionIsHierarchyEnabled)
    }

    mutating func synchronizeEntries(_ entries: [EntryModel]) {
        var prospectiveState = self
        prospectiveState.entries = entries
        let pendingTypeScrollTargetSurvives = pendingTypeScrollTargetId.map { targetID in
            prospectiveState.hierarchyProjectionIsActive
                ? prospectiveState.visibleSelectableEntryIDs(isNormalDirectoryPage: true).contains(targetID)
                : entries.contains(where: { $0.id == targetID })
        } ?? true
        self.entries = entries
        // Incoming roots를 반영한 hierarchy projection만 render throttle을 통과할 target으로 인정한다.
        if !pendingTypeScrollTargetSurvives {
            pendingTypeScrollTargetId = nil
        }
        reconcileSelectionWithVisibleEntries(preservesScrollIntent: true)
    }

    mutating func synchronizePresentation(
        entries: [EntryModel],
        sections _: [EntryViewLayoutSection],
        openWithApplications: [ApplicationInfo],
    ) {
        self.entries = entries
        entryOperations.commonApplicationsForSelectedFiles = openWithApplications
        self.entries = entries
        reconcileSelectionWithVisibleEntries(preservesScrollIntent: true)
    }

    public var hierarchyProjectionIsActive: Bool {
        mode == .list
            && !isCollectionMode
            && !hierarchy.rootPath.isEmpty
            && entryArrangements.groupKey == .none
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
                hasActiveGrouping: entryArrangements.groupKey != .none,
            ),
            sortKey: entryArrangements.sortKey,
            sortOrder: entryArrangements.sortOrder,
        )
    }

    var selectionProjectionIsHierarchyEnabled: Bool {
        !hierarchy.rootPath.isEmpty
    }

    mutating func advanceOutlineProjectionRevision() {
        outlineProjectionRevision &+= 1
    }

    mutating func reconcileSelectionWithVisibleEntries(preservesScrollIntent: Bool = false) {
        let previousShouldScrollToSelection = shouldScrollToSelection
        let previousSelectedIds = selectedIds
        let currentProjection = outlineProjection(isNormalDirectoryPage: selectionProjectionIsHierarchyEnabled)
        let visibleEntryIDs = Set(currentProjection.visibleSelectableEntryIDs)
        let remainingIds: Set<EntryModel.ID> = if preservesScrollIntent {
            if hierarchyProjectionIsActive {
                Set(entries.map(\.id)).union(hierarchy.nodesByID.values.flatMap(\.folder.children).map(\.id))
            } else {
                Set(entries.map(\.id))
            }
        } else {
            visibleEntryIDs
        }
        selectedIds = selectedIds.intersection(remainingIds)

        let projectionChanged = lastReconciledOutlineProjection.map {
            !$0.hasSameStructure(as: currentProjection)
        } ?? (visibleEntryIDs != lastVisibleSelectableEntryIDs)
        if projectionChanged {
            advanceOutlineProjectionRevision()
        }
        lastVisibleSelectableEntryIDs = visibleEntryIDs
        // revision bump 이후 projection을 재생성해 캐시와 카운터가 일치하도록 보존한다.
        // 구조가 동일하므로 hasSameStructure 비교에는 영향을 주지 않는다.
        lastReconciledOutlineProjection =
            outlineProjection(isNormalDirectoryPage: selectionProjectionIsHierarchyEnabled)

        guard !selectedIds.isEmpty else {
            lastSelectedId = nil
            rangeAnchorId = nil
            shouldScrollToSelection = false
            if preservesScrollIntent {
                shouldScrollToSelection = previousShouldScrollToSelection
            }
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
        if preservesScrollIntent {
            shouldScrollToSelection = previousShouldScrollToSelection
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
        activeAppendExpectedBatchIndices = [:]
        activeCollectionAppendPaths = [:]
        finishedCollectionAppendTokens = []
        collectionCoreFinished = false
        collectionStreamCompleted = false
        collectionIncompleteFailure = nil
        removedCollectionPaths = []
        entries = displayOrderItems
        pendingTypeScrollTargetId = nil

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

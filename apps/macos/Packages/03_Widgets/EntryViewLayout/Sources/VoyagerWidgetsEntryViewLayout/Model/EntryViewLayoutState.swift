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
    public var expectedCollectionReplaceBatchIndex = 0
    public var activeCollectionAppendExpectedBatchIndices: [Int: Int] = [:]
    public var finishedCollectionAppendTokens: Set<Int> = []
    public var nextCollectionAppendToken = 0
    public var collectionCoreFinished = false
    public var collectionStreamCompleted = false
    public var collectionIncompleteFailure: String?
    public var removedCollectionPaths: Set<String> = []

    /// When true, `displayItems` returns `collectionItems`; otherwise `entryOperations.items`.
    public var isCollectionMode: Bool = false

    /// Canonical display items: `collectionItems` in collection mode, `entryOperations.items` otherwise.
    public var displayItems: IdentifiedArrayOf<EntryModel> {
        isCollectionMode ? collectionItems : entryOperations.items
    }

    /// Ordered snapshot of `displayItems` for list/grid rendering.
    public var displayOrderItems: [EntryModel] {
        Array(displayItems)
    }

    public var entries: [EntryModel] = []

    public func visibleSelectableEntryIDs(isNormalDirectoryPage: Bool) -> [EntryModel.ID] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntryIDs
    }

    public func visibleSelectableEntries(isNormalDirectoryPage: Bool) -> [EntryModel] {
        outlineProjection(isNormalDirectoryPage: isNormalDirectoryPage).visibleSelectableEntries
    }

    public var hierarchyProjectionIsActive: Bool {
        mode == .list
            && !isCollectionMode
            && !hierarchy.rootPath.isEmpty
            && entryArrangements.groupKey == .none
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

    public init() {}

    public mutating func clearCollectionPresentation() {
        isCollectionMode = false
        collectionItems = []
        isCollectionContentLoading = false
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

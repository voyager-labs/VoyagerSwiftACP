import ComposableArchitecture
import CoreGraphics
import Foundation
import IdentifiedCollections
import SwiftUI
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
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

    public init() {}
}

import ComposableArchitecture
import CoreGraphics
import Foundation
import IdentifiedCollections
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

@ObservableState
struct EntryViewLayoutState: Equatable {
    enum Mode: String, Equatable, Codable, Sendable {
        case list
        case grid

        var isGridLayout: Bool {
            self == .grid
        }

        static func from(_ rawValue: String?) -> Mode? {
            rawValue.flatMap(Self.init(rawValue:))
        }
    }

    var mode: Mode = .list
    var entryOperations: EntryOperationsFeature.State = .init()
    var entryThumbnail: EntryThumbnailFeature.State = .init()
    var entryArrangements: EntryArrangementsFeature.State = .init()

    var currentPath: String = ""
    var selectedIds: Set<EntryModel.ID> = []
    var lastSelectedId: EntryModel.ID?
    var rangeAnchorId: EntryModel.ID?
    var shouldScrollToSelection: Bool = false
    var gridColumnCount: Int = 1
    var listVisibleColumns: [EntryListColumn] = EntryListColumn.defaultVisibleColumns

    var isDropTargeted: Bool = false
    var showHiddenFiles: Bool = false
    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize
    var savedScrollOffset: CGPoint?

    /// Items sourced from collection search results.
    var collectionItems: IdentifiedArrayOf<EntryModel> = []

    /// When true, `displayItems` returns `collectionItems`; otherwise `entryOperations.items`.
    var isCollectionMode: Bool = false

    /// Canonical display items: `collectionItems` in collection mode, `entryOperations.items` otherwise.
    var displayItems: IdentifiedArrayOf<EntryModel> {
        isCollectionMode ? collectionItems : entryOperations.items
    }

    /// Ordered snapshot of `displayItems` for list/grid rendering.
    var displayOrderItems: [EntryModel] {
        Array(displayItems)
    }

    var entries: [EntryModel] = []
}

import ComposableArchitecture
import CoreGraphics
import Foundation
import SwiftUI
import VoyagerShared

@ObservableState
struct EntryViewLayoutState: Equatable {
    var entryOperations: EntryOperationsFeature.State = .init()
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

    var entries: [EntryModel] = []
}

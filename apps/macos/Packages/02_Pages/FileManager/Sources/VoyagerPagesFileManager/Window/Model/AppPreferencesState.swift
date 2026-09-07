import CoreGraphics
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesEntryArrangements
import VoyagerShared

public struct AppPreferencesState: Equatable, Sendable {
    public var defaultStartPage: StartPage = .home
    public var showHiddenFiles: Bool = false
    public var viewLayoutMode: ViewLayoutMode = .list
    public var sortKey: SortKey = .name
    public var sortOrder: VoyagerShared.SortOrder = .ascending
    public var groupKey: GroupKey = .none

    public var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    public var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    public var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    public var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    public var sidebarVisible: Bool = true
    public var sidebarWidth: CGFloat = 220
    public var inspectorWidth: CGFloat = FileManagerInspectorLayoutMetrics.defaultWidth

    public init() {}
}

public extension AppPreferencesState {
    enum ViewLayoutMode: String, Equatable, Sendable {
        case list
        case grid
    }
}

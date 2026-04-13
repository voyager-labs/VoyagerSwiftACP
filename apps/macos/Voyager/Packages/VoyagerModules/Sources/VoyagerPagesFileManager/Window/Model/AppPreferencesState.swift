import CoreGraphics
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

public struct AppPreferencesState: Equatable, Sendable {
    public var showHiddenFiles: Bool
    public var viewLayout: EntryViewLayoutState.Mode
    public var sortKey: SortKey
    public var sortOrder: VoyagerWidgetsEntryViewLayout.SortOrder
    public var groupKey: GroupKey
    public var listIconSize: CGFloat
    public var gridIconSize: CGFloat
    public var listTextSize: CGFloat
    public var gridTextSize: CGFloat
    public var sidebarVisible: Bool
    public var sidebarWidth: CGFloat

    public init(
        showHiddenFiles: Bool = false,
        viewLayout: EntryViewLayoutState.Mode = .list,
        sortKey: SortKey = .name,
        sortOrder: VoyagerWidgetsEntryViewLayout.SortOrder = .ascending,
        groupKey: GroupKey = .none,
        listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize,
        gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize,
        listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize,
        gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize,
        sidebarVisible: Bool = true,
        sidebarWidth: CGFloat = 220,
    ) {
        self.showHiddenFiles = showHiddenFiles
        self.viewLayout = viewLayout
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.groupKey = groupKey
        self.listIconSize = listIconSize
        self.gridIconSize = gridIconSize
        self.listTextSize = listTextSize
        self.gridTextSize = gridTextSize
        self.sidebarVisible = sidebarVisible
        self.sidebarWidth = sidebarWidth
    }
}

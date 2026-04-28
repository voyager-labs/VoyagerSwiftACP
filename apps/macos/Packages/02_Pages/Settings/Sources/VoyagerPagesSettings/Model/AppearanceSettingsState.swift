import AppKit
import ComposableArchitecture
import VoyagerEntitiesAppPreferences
import VoyagerShared

@ObservableState
public struct AppearanceSettingsState: Equatable {
    var theme: AppTheme = .system
    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize
    var showHiddenFiles: Bool = false

    public init() {}
}

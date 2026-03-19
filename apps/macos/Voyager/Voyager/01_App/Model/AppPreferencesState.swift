import CoreGraphics
import Foundation
import VoyagerShared

struct AppPreferencesState: Equatable, Sendable {
    var showHiddenFiles: Bool = false
    var viewLayout: EntryViewLayoutState.Mode = .list
    var sortKey: SortKey = .name
    var sortOrder: SortOrder = .ascending
    var groupKey: GroupKey = .none

    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220

    static func load(from userDefaultsClient: UserDefaultsClient) -> Self {
        var state = AppPreferencesState()
        state.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
        state.viewLayout = EntryViewLayoutState.Mode(
            rawValue: userDefaultsClient.string(SettingsKeys.viewLayout) ?? "",
        ) ?? .list
        state.sortKey = SortKey(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortKey) ?? "",
        ) ?? .name
        state.sortOrder = SortOrder(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortOrder) ?? "",
        ) ?? .ascending
        state.groupKey = GroupKey(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.groupKey) ?? "",
        ) ?? .none

        if let listIconSize = readCGFloat(userDefaultsClient, SettingsKeys.listIconSize) {
            state.listIconSize = listIconSize
        }
        if let gridIconSize = readCGFloat(userDefaultsClient, SettingsKeys.gridIconSize) {
            state.gridIconSize = gridIconSize
        }
        if let listTextSize = readCGFloat(userDefaultsClient, SettingsKeys.listTextSize) {
            state.listTextSize = listTextSize
        }
        if let gridTextSize = readCGFloat(userDefaultsClient, SettingsKeys.gridTextSize) {
            state.gridTextSize = gridTextSize
        }

        state.sidebarVisible = userDefaultsClient.object(SettingsKeys.sidebarVisible) as? Bool ?? true
        if let sidebarWidth = userDefaultsClient.object(SettingsKeys.sidebarWidth) as? Double, sidebarWidth > 0 {
            state.sidebarWidth = CGFloat(sidebarWidth)
        }
        return state
    }
}

private func readCGFloat(_ userDefaultsClient: UserDefaultsClient, _ key: String) -> CGFloat? {
    if let value = userDefaultsClient.object(key) as? CGFloat {
        return value
    }
    if let value = userDefaultsClient.object(key) as? Double {
        return CGFloat(value)
    }
    return nil
}

import CoreGraphics
import Foundation
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

typealias AppPreferencesState = VoyagerPagesFileManager.AppPreferencesState

extension AppPreferencesState {
    static func load(from userDefaultsClient: UserDefaultsClient) -> Self {
        var state = AppPreferencesState()
        state.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
        state.viewLayout = EntryViewLayoutState.Mode(
            rawValue: userDefaultsClient.string(SettingsKeys.viewLayout) ?? "",
        ) ?? .list
        state.sortKey = VoyagerWidgetsEntryViewLayout.SortKey(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortKey) ?? "",
        ) ?? .name
        state.sortOrder = VoyagerWidgetsEntryViewLayout.SortOrder(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortOrder) ?? "",
        ) ?? .ascending
        state.groupKey = VoyagerWidgetsEntryViewLayout.GroupKey(
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

        // TODO: UserDefaults sidebar 저장 버그 수정 후 원복
        state.sidebarVisible = true
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

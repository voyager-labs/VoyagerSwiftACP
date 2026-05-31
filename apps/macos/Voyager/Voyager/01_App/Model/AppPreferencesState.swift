import CoreGraphics
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesEntryArrangements
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

struct AppPreferencesState: Equatable, Sendable {
    var showHiddenFiles: Bool = false
    var viewLayout: EntryViewLayoutState.Mode = .list
    var sortKey: SortKey = .name
    var sortOrder: VoyagerShared.SortOrder = .ascending
    var groupKey: GroupKey = .none

    var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
    var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
    var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
    var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize

    var sidebarVisible: Bool = true
    var sidebarWidth: CGFloat = 220
    var inspectorWidth: CGFloat = FileManagerInspectorLayoutMetrics.defaultWidth

    static func load(from userDefaultsClient: UserDefaultsClient) -> Self {
        var state = AppPreferencesState()
        state.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
        state.viewLayout = EntryViewLayoutState.Mode(
            rawValue: userDefaultsClient.string(SettingsKeys.viewLayout) ?? "",
        ) ?? .list
        state.sortKey = SortKey(
            rawValue: userDefaultsClient.string(EntryArrangementsPersistenceKey.sortKey) ?? "",
        ) ?? .name
        state.sortOrder = VoyagerShared.SortOrder(
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

        // TODO: UserDefaults sidebar 저장 버그 수정 후 원복
        state.sidebarVisible = true
        if let sidebarWidth = readPersistedCGFloat(userDefaultsClient, SettingsKeys.sidebarWidth) {
            state.sidebarWidth = sidebarWidth
        }
        if let inspectorWidth = readPersistedCGFloat(userDefaultsClient, SettingsKeys.inspectorWidth) {
            state.inspectorWidth = inspectorWidth
        }
        return state
    }

    func toPackageState() -> VoyagerPagesFileManager.AppPreferencesState {
        var result = VoyagerPagesFileManager.AppPreferencesState()
        result.showHiddenFiles = showHiddenFiles
        result.viewLayoutMode = .init(rawValue: viewLayout.rawValue) ?? .list
        result.sortKey = sortKey
        result.sortOrder = sortOrder
        result.groupKey = groupKey
        result.listIconSize = listIconSize
        result.gridIconSize = gridIconSize
        result.listTextSize = listTextSize
        result.gridTextSize = gridTextSize
        result.sidebarVisible = sidebarVisible
        result.sidebarWidth = sidebarWidth
        result.inspectorWidth = inspectorWidth
        return result
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

private func readPersistedCGFloat(_ userDefaultsClient: UserDefaultsClient, _ key: String) -> CGFloat? {
    if let value = readCGFloat(userDefaultsClient, key), value > 0 {
        return value
    }
    let value = userDefaultsClient.double(key)
    return value > 0 ? CGFloat(value) : nil
}

import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct AppearanceSettingsFeature {
    typealias State = AppearanceSettingsState
    typealias Action = AppearanceSettingsAction

    @Dependency(\.appearanceSettingsClient)
    var appearanceSettingsClient: AppearanceSettingsClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient: UserDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadSettings:
                state.theme = appearanceSettingsClient.loadTheme()

                let savedListIconSize = userDefaultsClient.object(SettingsKeys.listIconSize) as? CGFloat
                if let listIconSize = savedListIconSize {
                    state.listIconSize = listIconSize
                }

                let savedGridIconSize = userDefaultsClient.object(SettingsKeys.gridIconSize) as? CGFloat
                if let gridIconSize = savedGridIconSize {
                    state.gridIconSize = gridIconSize
                }

                let savedListTextSize = userDefaultsClient.object(SettingsKeys.listTextSize) as? CGFloat
                if let listTextSize = savedListTextSize {
                    state.listTextSize = listTextSize
                }

                let savedGridTextSize = userDefaultsClient.object(SettingsKeys.gridTextSize) as? CGFloat
                if let gridTextSize = savedGridTextSize {
                    state.gridTextSize = gridTextSize
                }

                state.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)

                return .none

            case let .setTheme(theme):
                state.theme = theme
                userDefaultsClient.setObject(theme.rawValue, SettingsKeys.theme)
                return .run { [appearanceSettingsClient] _ in
                    await appearanceSettingsClient.applyTheme(theme)
                }

            case let .setListIconSize(size):
                state.listIconSize = size
                userDefaultsClient.setObject(size, SettingsKeys.listIconSize)
                return .none

            case let .setGridIconSize(size):
                state.gridIconSize = size
                userDefaultsClient.setObject(size, SettingsKeys.gridIconSize)
                return .none

            case let .setListTextSize(size):
                state.listTextSize = size
                userDefaultsClient.setObject(size, SettingsKeys.listTextSize)
                return .none

            case let .setGridTextSize(size):
                state.gridTextSize = size
                userDefaultsClient.setObject(size, SettingsKeys.gridTextSize)
                return .none

            case let .setShowHiddenFiles(isEnabled):
                state.showHiddenFiles = isEnabled
                userDefaultsClient.setBool(isEnabled, SettingsKeys.showHiddenFiles)
                return .none
            }
        }
    }
}

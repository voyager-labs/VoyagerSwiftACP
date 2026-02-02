import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct AppearanceSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var theme: AppTheme = .system
        var listIconSize: CGFloat = AppearanceSettingsDefaults.listIconSize
        var gridIconSize: CGFloat = AppearanceSettingsDefaults.gridIconSize
        var listTextSize: CGFloat = AppearanceSettingsDefaults.listTextSize
        var gridTextSize: CGFloat = AppearanceSettingsDefaults.gridTextSize
        var showHiddenFiles: Bool = false
    }

    enum Action: Sendable {
        case onAppear
        case loadSettings
        case setTheme(AppTheme)
        case setListIconSize(CGFloat)
        case setGridIconSize(CGFloat)
        case setListTextSize(CGFloat)
        case setGridTextSize(CGFloat)
        case setShowHiddenFiles(Bool)
    }

    @Dependency(\.appearanceSettingsClient)
    var appearanceSettingsClient: AppearanceSettingsClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient: UserDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadSettings)

            case .loadSettings:
                // 테마 로드
                state.theme = appearanceSettingsClient.loadTheme()

                // 아이콘 크기 로드
                let savedListIconSize = userDefaultsClient.object(SettingsKeys.listIconSize) as? CGFloat
                if let listIconSize = savedListIconSize {
                    state.listIconSize = listIconSize
                }

                let savedGridIconSize = userDefaultsClient.object(SettingsKeys.gridIconSize) as? CGFloat
                if let gridIconSize = savedGridIconSize {
                    state.gridIconSize = gridIconSize
                }

                // 텍스트 크기 로드
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

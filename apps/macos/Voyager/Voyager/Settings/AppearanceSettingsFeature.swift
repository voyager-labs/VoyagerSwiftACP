import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct AppearanceSettingsFeature {
    @ObservableState
    struct State: Equatable {
        var theme: AppTheme = .system
        var listIconSize: CGFloat = 20
        var gridIconSize: CGFloat = 64
        var listTextSize: CGFloat = 13
        var gridTextSize: CGFloat = 12
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

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadSettings)

            case .loadSettings:
                // 테마 로드
                state.theme = appearanceSettingsClient.loadTheme()

                // 아이콘 크기 로드
                let savedListIconSize = UserDefaults.standard.object(forKey: SettingsKeys.listIconSize) as? CGFloat
                if let listIconSize = savedListIconSize {
                    state.listIconSize = listIconSize
                }

                let savedGridIconSize = UserDefaults.standard.object(forKey: SettingsKeys.gridIconSize) as? CGFloat
                if let gridIconSize = savedGridIconSize {
                    state.gridIconSize = gridIconSize
                }

                // 텍스트 크기 로드
                let savedListTextSize = UserDefaults.standard.object(forKey: SettingsKeys.listTextSize) as? CGFloat
                if let listTextSize = savedListTextSize {
                    state.listTextSize = listTextSize
                }

                let savedGridTextSize = UserDefaults.standard.object(forKey: SettingsKeys.gridTextSize) as? CGFloat
                if let gridTextSize = savedGridTextSize {
                    state.gridTextSize = gridTextSize
                }

                state.showHiddenFiles = UserDefaults.standard.bool(forKey: SettingsKeys.showHiddenFiles)

                return .none

            case let .setTheme(theme):
                state.theme = theme
                UserDefaults.standard.set(theme.rawValue, forKey: SettingsKeys.theme)
                return .run { [appearanceSettingsClient] _ in
                    await appearanceSettingsClient.applyTheme(theme)
                }

            case let .setListIconSize(size):
                state.listIconSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.listIconSize)
                return .none

            case let .setGridIconSize(size):
                state.gridIconSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.gridIconSize)
                return .none

            case let .setListTextSize(size):
                state.listTextSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.listTextSize)
                return .none

            case let .setGridTextSize(size):
                state.gridTextSize = size
                UserDefaults.standard.set(size, forKey: SettingsKeys.gridTextSize)
                return .none

            case let .setShowHiddenFiles(isEnabled):
                state.showHiddenFiles = isEnabled
                UserDefaults.standard.set(isEnabled, forKey: SettingsKeys.showHiddenFiles)
                return .none
            }
        }
    }
}

import ComposableArchitecture
import VoyagerPagesSettings

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    var body: some Reducer<State, Action> {
        Scope(state: \.lifecycle, action: \.lifecycle) {
            AppLifecycleFeature()
        }
        Scope(state: \.appPreferences, action: \.appPreferences) {
            AppPreferencesFeature()
        }
        Scope(state: \.windowManager, action: \.windowManager) {
            WindowManagerFeature()
        }
        Scope(state: \.updater, action: \.updater) {
            UpdaterFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.menuCommands, action: \.menuCommands) {
            MenuCommandsFeature()
        }

        Reduce { state, action in
            let effect: Effect<Action>
            switch action {
            case .lifecycle(.launch(.willFinishLaunching)):
                effect = .send(.appPreferences(.load))

            case let .lifecycle(.delegate(delegateAction)):
                switch delegateAction {
                case .openInitialWindowIfNeeded:
                    effect = .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

                case let .reopenWindowIfNeeded(hasVisibleWindows):
                    effect =
                        .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))
                }

            case .lifecycle:
                effect = .none

            case let .appPreferences(.delegate(.updated(preferences))):
                state.appPreferences = preferences
                effect = .send(.windowManager(.lifecycle(.applyAppPreferences(preferences))))

            case .appPreferences:
                effect = .none

            case let .menuCommands(.delegate(.windowManager(action))):
                effect = .send(.windowManager(action))

            case let .menuCommands(.delegate(.updater(action))):
                effect = .send(.updater(action))

            case .menuCommands:
                effect = .none

            case .settings(.general(.checkForUpdates)):
                effect = .send(.updater(.checkForUpdates))

            case let .settings(.general(.toggleAutomaticUpdate(enabled))):
                effect = .send(.updater(.setAutomaticUpdate(enabled)))

            case .windowManager, .updater, .settings:
                effect = .none
            }

            // menuCommands는 윈도우 상태를 기반으로 한 파생 상태이므로 루트 리듀서에서 항상 동기화한다.
            state.menuCommands = MenuCommandsState(state: state)
            return effect
        }
    }
}

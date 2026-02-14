import ComposableArchitecture

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    var body: some Reducer<State, Action> {
        Scope(state: \.lifecycle, action: \.lifecycle) {
            AppLifecycleFeature()
        }
        Scope(state: \.windowManager, action: \.windowManager) {
            WindowManagerFeature()
        }
        Scope(state: \.updater, action: \.updater) {
            UpdaterFeature()
        }
        Scope(state: \.menuCommands, action: \.menuCommands) {
            MenuCommandsFeature()
        }

        Reduce { state, action in
            let effect: Effect<Action> = switch action {
            case let .lifecycle(.delegate(delegateAction)):
                switch delegateAction {
                case .openInitialWindowIfNeeded:
                    .send(.windowManager(.openInitialWindowIfNeeded))

                case let .reopenWindowIfNeeded(hasVisibleWindows):
                    .send(.windowManager(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows)))
                }

            case .lifecycle:
                .none

            case let .menuCommands(.delegate(delegateAction)):
                switch delegateAction {
                case let .dispatchToWindowManager(action):
                    .send(.windowManager(action))

                case let .dispatchToUpdater(action):
                    .send(.updater(action))
                }

            case .menuCommands:
                .none

            case .windowManager, .updater:
                .none
            }

            // menuCommands는 윈도우 상태를 기반으로 한 파생 상태이므로 루트 리듀서에서 항상 동기화한다.
            state.menuCommands = MenuCommandsState(state: state)
            return effect
        }
    }
}

import ComposableArchitecture

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
        Scope(state: \.menuCommands, action: \.menuCommands) {
            MenuCommandsFeature()
        }

        Reduce { state, action in
            let effect: Effect<Action>
            switch action {
            case .lifecycle(.willFinishLaunching):
                effect = .send(.appPreferences(.load))

            case let .lifecycle(.delegate(delegateAction)):
                switch delegateAction {
                case .openInitialWindowIfNeeded:
                    effect = .send(.windowManager(.openInitialWindowIfNeeded))

                case let .reopenWindowIfNeeded(hasVisibleWindows):
                    effect = .send(.windowManager(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows)))
                }

            case .lifecycle:
                effect = .none

            case let .appPreferences(.delegate(.updated(preferences))):
                state.appPreferences = preferences
                effect = .send(.windowManager(.applyAppPreferences(preferences)))

            case .appPreferences:
                effect = .none

            case let .menuCommands(.perform(command)):
                effect = routeMenuCommand(command)

            case .menuCommands:
                effect = .none

            case .windowManager, .updater:
                effect = .none
            }

            // menuCommands는 윈도우 상태를 기반으로 한 파생 상태이므로 루트 리듀서에서 항상 동기화한다.
            state.menuCommands = MenuCommandsState(state: state)
            return effect
        }
    }

    private func routeMenuCommand(_ command: MenuCommandItem.Command) -> Effect<Action> {
        switch command {
        case let .app(appCommand):
            routeAppCommand(appCommand)
        case let .view(viewCommand):
            routeViewCommand(viewCommand)
        case let .edit(editCommand):
            routeEditCommand(editCommand)
        }
    }

    private func routeAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action> {
        switch command {
        case let .newWindow(path):
            .send(.windowManager(.newWindow(path: path)))
        case let .newTab(path):
            .send(.windowManager(.newTab(path: path)))
        case .newFolder:
            .send(.windowManager(.newFolder))
        case .open:
            .send(.windowManager(.open))
        case .quickLook:
            .send(.windowManager(.quickLook))
        case .saveCollection:
            .send(.windowManager(.saveCollection))
        case .saveCollectionAs:
            .send(.windowManager(.saveCollectionAs))
        case .closeFocusedWindow:
            .send(.windowManager(.closeFocusedWindow))
        case .closeAllWindows:
            .send(.windowManager(.closeAllWindows))
        case .goBack:
            .send(.windowManager(.goBack))
        case .goForward:
            .send(.windowManager(.goForward))
        case .goToEnclosingDirectory:
            .send(.windowManager(.goToEnclosingDirectory))
        case .checkForUpdates:
            .send(.updater(.checkForUpdates))
        case let .setAutomaticUpdate(enabled):
            .send(.updater(.setAutomaticUpdate(enabled)))
        }
    }

    private func routeViewCommand(_ command: MenuCommandItem.ViewCommand) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            .send(.windowManager(.toggleSidebar))
        case .toggleShowHiddenFiles:
            .send(.windowManager(.toggleShowHiddenFiles))
        case let .setViewLayout(layout):
            .send(.windowManager(.setViewLayout(layout)))
        case let .setGroupKey(key):
            .send(.windowManager(.setGroupKey(key)))
        case let .setSortKey(key):
            .send(.windowManager(.setSortKey(key)))
        case let .setSortOrder(order):
            .send(.windowManager(.setSortOrder(order)))
        }
    }

    private func routeEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action> {
        switch command {
        case .requestUndo:
            .send(.windowManager(.requestUndo))
        case .requestRedo:
            .send(.windowManager(.requestRedo))
        case .toggleComposer:
            .send(.windowManager(.toggleComposer))
        case .cut:
            .send(.windowManager(.cut))
        case .copy:
            .send(.windowManager(.copy))
        case .paste:
            .send(.windowManager(.paste))
        case .duplicate:
            .send(.windowManager(.duplicate))
        case .makeAlias:
            .send(.windowManager(.makeAlias))
        case .selectAll:
            .send(.windowManager(.selectAll))
        case .copyAbsolutePaths:
            .send(.windowManager(.copyAbsolutePaths))
        case .copyURLs:
            .send(.windowManager(.copyURLs))
        }
    }
}

import ComposableArchitecture

@Reducer
struct MenuCommandsAppFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .perform(.app(command)) = action else {
                return .none
            }

            switch command {
            case let .newWindow(path):
                return .send(.delegate(.dispatchToWindowManager(.newWindow(path: path))))

            case let .newTab(path):
                return .send(.delegate(.dispatchToWindowManager(.newTab(path: path))))

            case .newFolder:
                return .send(.delegate(.dispatchToWindowManager(.newFolder)))

            case .open:
                return .send(.delegate(.dispatchToWindowManager(.open)))

            case .quickLook:
                return .send(.delegate(.dispatchToWindowManager(.quickLook)))

            case .saveCollection:
                return .send(.delegate(.dispatchToWindowManager(.saveCollection)))

            case .saveCollectionAs:
                return .send(.delegate(.dispatchToWindowManager(.saveCollectionAs)))

            case .closeFocusedWindow:
                return .send(.delegate(.dispatchToWindowManager(.closeFocusedWindow)))

            case .closeAllWindows:
                return .send(.delegate(.dispatchToWindowManager(.closeAllWindows)))

            case .goBack:
                return .send(.delegate(.dispatchToWindowManager(.goBack)))

            case .goForward:
                return .send(.delegate(.dispatchToWindowManager(.goForward)))

            case .goToEnclosingDirectory:
                return .send(.delegate(.dispatchToWindowManager(.goToEnclosingDirectory)))

            case .checkForUpdates:
                return .send(.delegate(.dispatchToUpdater(.checkForUpdates)))

            case let .setAutomaticUpdate(enabled):
                return .send(.delegate(.dispatchToUpdater(.setAutomaticUpdate(enabled))))
            }
        }
    }
}

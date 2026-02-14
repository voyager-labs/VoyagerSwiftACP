import ComposableArchitecture

@Reducer
struct MenuCommandsViewFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .perform(.view(command)) = action else {
                return .none
            }

            switch command {
            case .toggleSidebar:
                return .send(.delegate(.dispatchToWindowManager(.toggleSidebar)))

            case .toggleShowHiddenFiles:
                return .send(.delegate(.dispatchToWindowManager(.toggleShowHiddenFiles)))

            case let .setViewLayout(layout):
                return .send(.delegate(.dispatchToWindowManager(.setViewLayout(layout))))

            case let .setGroupKey(key):
                return .send(.delegate(.dispatchToWindowManager(.setGroupKey(key))))

            case let .setSortKey(key):
                return .send(.delegate(.dispatchToWindowManager(.setSortKey(key))))

            case let .setSortOrder(order):
                return .send(.delegate(.dispatchToWindowManager(.setSortOrder(order))))
            }
        }
    }
}

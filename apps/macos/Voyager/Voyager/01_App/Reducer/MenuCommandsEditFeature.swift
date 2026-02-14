import ComposableArchitecture

@Reducer
struct MenuCommandsEditFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .perform(.edit(command)) = action else {
                return .none
            }

            switch command {
            case .requestUndo:
                return .send(.delegate(.dispatchToWindowManager(.requestUndo)))

            case .requestRedo:
                return .send(.delegate(.dispatchToWindowManager(.requestRedo)))

            case .toggleComposer:
                return .send(.delegate(.dispatchToWindowManager(.toggleComposer)))

            case .cut:
                return .send(.delegate(.dispatchToWindowManager(.cut)))

            case .copy:
                return .send(.delegate(.dispatchToWindowManager(.copy)))

            case .paste:
                return .send(.delegate(.dispatchToWindowManager(.paste)))

            case .duplicate:
                return .send(.delegate(.dispatchToWindowManager(.duplicate)))

            case .makeAlias:
                return .send(.delegate(.dispatchToWindowManager(.makeAlias)))

            case .selectAll:
                return .send(.delegate(.dispatchToWindowManager(.selectAll)))

            case .copyAbsolutePaths:
                return .send(.delegate(.dispatchToWindowManager(.copyAbsolutePaths)))

            case .copyURLs:
                return .send(.delegate(.dispatchToWindowManager(.copyURLs)))
            }
        }
    }
}

import ComposableArchitecture

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarContentTabSyncReducer()
        FileManagerSidebarEntryDropRoutingReducer()
    }
}

@Reducer
struct FileManagerSidebarContentTabSyncReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.syncContentTabSidebarItems(items)):
                state.contentTabSidebarItems = items
                return .none
            default:
                return .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarEntryDropRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .view(.entryDropRequested(request)) = action else {
                return .none
            }
            return .send(.delegate(.entryDropRequested(request)))
        }
    }
}

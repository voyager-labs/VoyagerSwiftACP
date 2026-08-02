import ComposableArchitecture

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarContentTabSyncReducer()
        FileManagerSidebarContentTabSelectionRoutingReducer()
        FileManagerSidebarContentTabPinRoutingReducer()
        FileManagerSidebarEntryDropRoutingReducer()
        FileManagerSidebarTopNavigationReorderRoutingReducer()
        FileManagerSidebarPresentationRoutingReducer()
    }
}

@Reducer
struct FileManagerSidebarPresentationRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case .view(.dismissTopNavigationPresentation) = action else { return .none }
            return .send(.delegate(.dismissTopNavigationPresentation))
        }
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
struct FileManagerSidebarContentTabSelectionRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.toggleContentTabSelection(id)):
                .send(.delegate(.toggleContentTabSelection(id)))

            case let .view(.selectContentTabRange(to: id)):
                .send(.delegate(.selectContentTabRange(to: id)))

            case .view(.collapseContentTabSelectionToActive):
                .send(.delegate(.collapseContentTabSelectionToActive))

            default:
                .none
            }
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabPinRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.pinContentTab(id)):
                .send(.delegate(.pinContentTab(id)))

            case let .view(.unpinContentTab(id)):
                .send(.delegate(.unpinContentTab(id)))

            case let .view(.setSelectedContentTabsPinned(target)):
                .send(.delegate(.setSelectedContentTabsPinned(target: target)))

            default:
                .none
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

@Reducer
struct FileManagerSidebarTopNavigationReorderRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .view(.fileManagerTopNavigationReorderRequested(sourceID, anchorID, placement)) = action
            else {
                return .none
            }
            return .send(.delegate(.fileManagerTopNavigationReorderRequested(
                sourceID: sourceID,
                anchorID: anchorID,
                placement: placement,
            )))
        }
    }
}

import ComposableArchitecture

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarContentTabMoveReducer()
        FileManagerSidebarContentTabSyncReducer()
        FileManagerSidebarContentTabSelectionRoutingReducer()
        FileManagerSidebarContentTabPinRoutingReducer()
        FileManagerSidebarEntryDropRoutingReducer()
        FileManagerSidebarContentTabReorderRoutingReducer()
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
struct FileManagerSidebarContentTabReorderRoutingReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .view(.contentTabReorderRequested(sourceID, targetID, placement)) = action else {
                return .none
            }
            return .send(.delegate(.contentTabReorderRequested(
                sourceID: sourceID,
                targetID: targetID,
                placement: placement,
            )))
        }
    }
}

@Reducer
struct FileManagerSidebarContentTabMoveReducer {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.moveContentTab(tabID, targetWindowID)):
                guard state.pendingContentTabMoveRequest == nil,
                      let sourceWindowID = state.currentWindowID,
                      state.contentTabSidebarItems.contains(where: { $0.id == tabID })
                else { return .none }
                let availableTargets = ContentTabMoveProjection.availableTargets(
                    state.contentTabMoveTargets,
                    currentWindowID: sourceWindowID,
                    tabID: tabID,
                )
                guard availableTargets.contains(where: { $0.windowID == targetWindowID }) else {
                    return .none
                }

                let request = ContentTabMoveRequest(
                    requestID: uuid(),
                    sourceWindowID: sourceWindowID,
                    tabID: tabID,
                    targetWindowID: targetWindowID,
                )
                state.pendingContentTabMoveRequest = request
                return .send(.delegate(.requestContentTabMove(request)))

            case let .view(.receiveContentTabDrag(payload)):
                guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
                      let currentWindowID = state.currentWindowID,
                      currentWindowID != payload.sourceWindowID,
                      state.pendingContentTabMoveRequest == nil
                else { return .none }
                return .send(.delegate(.receiveContentTabDrag(payload)))

            default:
                return .none
            }
        }
    }
}

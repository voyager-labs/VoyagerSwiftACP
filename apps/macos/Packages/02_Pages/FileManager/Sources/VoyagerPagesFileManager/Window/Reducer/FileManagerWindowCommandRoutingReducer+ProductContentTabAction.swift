import ComposableArchitecture

extension FileManagerWindowCommandRoutingReducer {
    func routeContentTabProductCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .closeActiveContentTab:
            return state.contentTabs.activeTabID.map {
                Effect<Action>.send(.closeContentTabRequested($0))
            } ?? .none
        case .closeSelectedContentTabs:
            return Effect<Action>.send(.requestCloseSelectedContentTabs)
        case .restoreLastClosedContentTab:
            return handleRestoreLastClosedContentTab(state: &state)
        case let .duplicateContentTab(sourceID):
            return handleDuplicateContentTabRequested(sourceID: sourceID, state: &state)
        case .duplicateActiveContentTab:
            guard let activeTabID = state.contentTabs.activeTabID else { return .none }
            return handleDuplicateContentTabRequested(sourceID: activeTabID, state: &state)
        case .duplicateSelectedContentTabs:
            return handleDuplicateSelectedContentTabsRequested(state: &state)
        case let .contentTabAction(request, source):
            return handleProductContentTabAction(request, source: source, state: &state)
        default:
            return nil
        }
    }

    func handleProductContentTabAction(
        _ request: ContentTabProductActionRequest,
        source: ContentTabActionSource,
        state: inout State,
    ) -> Effect<Action> {
        switch request {
        case .closeActive:
            return state.contentTabs.activeTabID.map {
                Effect<Action>.send(.closeContentTabRequestedWithSource($0, source))
            } ?? Effect<Action>.none
        case .closeSelected:
            return Effect<Action>.send(.requestCloseSelectedTabs(source))
        case .restoreLastClosed:
            return handleRestoreLastClosedContentTab(state: &state, actionSource: source)
        case let .duplicate(sourceID):
            return handleDuplicateContentTabRequested(sourceID: sourceID, state: &state, actionSource: source)
        case .duplicateActive:
            guard let activeTabID = state.contentTabs.activeTabID else { return .none }
            return handleDuplicateContentTabRequested(
                sourceID: activeTabID,
                state: &state,
                actionSource: source,
            )
        case .duplicateSelected:
            return handleDuplicateSelectedContentTabsRequested(state: &state, actionSource: source)
        }
    }
}

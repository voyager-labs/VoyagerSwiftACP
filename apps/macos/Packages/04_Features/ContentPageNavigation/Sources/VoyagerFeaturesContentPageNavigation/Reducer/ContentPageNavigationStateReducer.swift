import ComposableArchitecture

@Reducer
struct ContentPageNavigationStateReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    init() {}

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .internal(.rollbackBackHistoryOnce):
                return rollbackBackHistoryOnce(state: &state)

            case let .internal(.restoreHistory(back, forward)):
                state.backHistory = back
                state.forwardHistory = forward
                return .none

            case let .internal(.appendBackHistory(entry)):
                return appendBackHistory(entry, state: &state)

            case .internal(.clearForwardHistory):
                return clearForwardHistory(state: &state)

            case let .internal(.setNavigationState(navigationState)),
                 let .internal(.applyPinnedPeerNavigationState(navigationState)):
                return setNavigationState(navigationState, state: &state)

            case let .internal(.setPendingNavigation(pending)):
                return setPendingNavigation(pending, state: &state)

            default:
                return .none
            }
        }
    }

    private func rollbackBackHistoryOnce(
        state: inout State,
    ) -> Effect<Action> {
        if !state.backHistory.isEmpty {
            state.backHistory.removeLast()
        }
        return .none
    }

    private func appendBackHistory(
        _ entry: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        state.appendBackHistory(entry)
        return .none
    }

    private func clearForwardHistory(
        state: inout State,
    ) -> Effect<Action> {
        state.forwardHistory = []
        return .none
    }

    private func setNavigationState(
        _ navigationState: ContentPageNavigationRoute,
        state: inout State,
    ) -> Effect<Action> {
        state.navigationState = navigationState
        return .none
    }

    private func setPendingNavigation(
        _ pending: ContentPageNavigationPending?,
        state: inout State,
    ) -> Effect<Action> {
        state.pendingNavigation = pending
        return .none
    }
}

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
                rollbackBackHistoryOnce(state: &state)

            case let .internal(.appendBackHistory(entry)):
                appendBackHistory(entry, state: &state)

            case .internal(.clearForwardHistory):
                clearForwardHistory(state: &state)

            case let .internal(.setNavigationState(navigationState)):
                setNavigationState(navigationState, state: &state)

            case let .internal(.setPendingNavigation(pending)):
                setPendingNavigation(pending, state: &state)

            default:
                .none
            }
        }
    }

    private func rollbackBackHistoryOnce(
        state: inout State
    ) -> Effect<Action> {
        if !state.backHistory.isEmpty {
            state.backHistory.removeLast()
        }
        return .none
    }

    private func appendBackHistory(
        _ entry: ContentPageNavigationHistorySnapshot,
        state: inout State
    ) -> Effect<Action> {
        state.appendBackHistory(entry)
        return .none
    }

    private func clearForwardHistory(
        state: inout State
    ) -> Effect<Action> {
        state.forwardHistory = []
        return .none
    }

    private func setNavigationState(
        _ navigationState: ContentPageNavigationRoute,
        state: inout State
    ) -> Effect<Action> {
        state.navigationState = navigationState
        return .none
    }

    private func setPendingNavigation(
        _ pending: ContentPageNavigationPending?,
        state: inout State
    ) -> Effect<Action> {
        state.pendingNavigation = pending
        return .none
    }
}

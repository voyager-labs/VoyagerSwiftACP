import ComposableArchitecture

@Reducer
struct ContentPageNavigationHistoryReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.performNavigation(pending)):
                performNavigation(pending, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigation(
        _ pending: ContentPageNavigationPending,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(state: &state)
        case .forward:
            performForwardNavigation(state: &state)
        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                state: &state,
            )
        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(state: &state)
        }
    }

    private func performBackNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let entry = state.backHistory.popLast() else { return .none }
        state.appendForwardHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
        )
    }

    private func performForwardNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let entry = state.forwardHistory.popLast() else { return .none }
        state.appendBackHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        if isBackHistory {
            let backCount = state.backHistory.count
            guard index >= 0, index < backCount else { return .none }
            let offset = backCount - index - 1
            var entry = state.backHistory.removeLast()
            var newForwardHistory: [ContentPageNavigationHistorySnapshot] = []
            for _ in 0 ..< offset {
                newForwardHistory.append(entry)
                entry = state.backHistory.removeLast()
            }
            state.appendForwardHistory(currentSnapshot)
            newForwardHistory.reversed().forEach { state.appendForwardHistory($0) }
            let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
            return historyNavigationEffects(
                previousNavigationState: previousNavigationState,
                nextNavigationState: state.navigationState,
            )
        }

        let forwardCount = state.forwardHistory.count
        guard index >= 0, index < forwardCount else { return .none }
        let offset = forwardCount - index - 1
        var entry = state.forwardHistory.removeLast()
        var newBackHistory: [ContentPageNavigationHistorySnapshot] = []
        for _ in 0 ..< offset {
            newBackHistory.append(entry)
            entry = state.forwardHistory.removeLast()
        }
        state.appendBackHistory(currentSnapshot)
        newBackHistory.reversed().forEach { state.appendBackHistory($0) }
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
        )
    }

    private func performEnclosingDirectoryNavigation(
        state: inout State,
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        guard let path = state.enclosingDirectoryPath else { return .none }
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        let previousNavigationState = state.navigationState
        state.navigationState = .folder(path)
        return historyNavigationEffects(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
        )
    }

    private func historyNavigationEffects(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        let shouldResetComposer = !nextNavigationState.isCollection
        if shouldResetComposer {
            effects.append(.send(.delegate(.resetComposer)))
        }

        effects.append(
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: nextNavigationState))),
        )
        effects.append(.send(.delegate(.navigateToState(nextNavigationState))))

        return .concatenate(effects)
    }

    private func applyContentPageNavigationHistorySnapshot(
        state: inout State,
        entry: ContentPageNavigationHistorySnapshot,
    ) -> ContentPageNavigationRoute {
        let previousNavigationState = state.navigationState
        state.navigationState = entry.navigationState
        return previousNavigationState
    }
}

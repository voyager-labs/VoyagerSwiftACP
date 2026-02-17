import ComposableArchitecture

@Reducer
struct ContentPageNavigationHistoryReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .performNavigation(pending, currentSnapshot):
                performNavigation(pending, currentSnapshot: currentSnapshot, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigation(
        _ pending: ContentPageNavigationPending,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(currentSnapshot: currentSnapshot, state: &state)
        case .forward:
            performForwardNavigation(currentSnapshot: currentSnapshot, state: &state)
        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                currentSnapshot: currentSnapshot,
                state: &state,
            )
        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(currentSnapshot: currentSnapshot, state: &state)
        }
    }

    private func performBackNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.backHistory.popLast() else { return .none }
        state.appendForwardHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performForwardNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let entry = state.forwardHistory.popLast() else { return .none }
        state.appendBackHistory(currentSnapshot)
        let previousNavigationState = applyContentPageNavigationHistorySnapshot(state: &state, entry: entry)
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
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
            return .merge(
                .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
                .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
                .send(.delegate(.navigateToState(state.navigationState))),
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
        return .merge(
            .send(.delegate(.applyContentPageNavigationHistorySnapshot(entry))),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
    }

    private func performEnclosingDirectoryNavigation(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        guard let path = state.enclosingDirectoryPath else { return .none }
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        let previousNavigationState = state.navigationState
        state.navigationState = .folder(path)
        return .merge(
            .send(.delegate(.resetComposer)),
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: state.navigationState))),
            .send(.delegate(.navigateToState(state.navigationState))),
        )
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

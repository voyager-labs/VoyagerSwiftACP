import ComposableArchitecture
import Foundation

@Reducer
struct ContentPageNavigationDirectReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    init() {}

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.performNavigateToPath(path)):
                performNavigateToPath(path, state: &state)

            case .internal(.performShowRecents):
                performShowRecents(state: &state)

            case .internal(.performShowComputer):
                performShowComputer(state: &state)

            case let .internal(.performShowTag(tagName)):
                performShowTag(tagName, state: &state)

            case let .internal(.prepareCollectionFileOpen(url)):
                performPrepareCollectionFileOpen(url, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigateToPath(
        _ path: String,
        state: inout State
    ) -> Effect<Action> {
        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        let shouldRecordHistory = path != state.currentPath

        if shouldRecordHistory {
            state.appendBackHistory(currentSnapshot)
            state.forwardHistory = []
        }

        state.navigationState = .folder(path)

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: shouldRecordHistory
        )
    }

    private func performShowRecents(
        state: inout State
    ) -> Effect<Action> {
        if case .recents = state.navigationState {
            return .none
        }

        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .recents

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true
        )
    }

    private func performShowComputer(
        state: inout State
    ) -> Effect<Action> {
        if case .computer = state.navigationState {
            return .none
        }

        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .computer

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true
        )
    }

    private func performShowTag(
        _ tagName: String,
        state: inout State
    ) -> Effect<Action> {
        if case let .tags(currentTagName) = state.navigationState,
           currentTagName == tagName
        {
            return .none
        }

        let currentSnapshot = state.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .tags(tagName)

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true
        )
    }

    private func performPrepareCollectionFileOpen(
        _: URL,
        state: inout State
    ) -> Effect<Action> {
        if case .collection = state.navigationState {
            return .none
        }

        let previousSnapshot = state.makeContentPageNavigationHistorySnapshot()
        state.appendBackHistory(previousSnapshot)
        state.forwardHistory = []
        return .none
    }

    private func directNavigationEffect(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
        shouldResetComposer: Bool
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        if shouldResetComposer {
            effects.append(.send(.delegate(.resetComposer)))
        }

        effects.append(
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: nextNavigationState)))
        )
        effects.append(.send(.delegate(.navigateToState(nextNavigationState))))

        return .concatenate(effects)
    }
}

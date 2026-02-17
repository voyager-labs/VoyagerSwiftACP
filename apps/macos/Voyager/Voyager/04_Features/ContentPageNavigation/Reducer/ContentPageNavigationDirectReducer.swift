import ComposableArchitecture
import Foundation

@Reducer
struct ContentPageNavigationDirectReducer {
    typealias State = ContentPageNavigationState
    typealias Action = ContentPageNavigationAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .performNavigateToPath(path, currentSnapshot):
                performNavigateToPath(path, currentSnapshot: currentSnapshot, state: &state)

            case let .performShowRecents(currentSnapshot):
                performShowRecents(currentSnapshot: currentSnapshot, state: &state)

            case let .performShowComputer(currentSnapshot):
                performShowComputer(currentSnapshot: currentSnapshot, state: &state)

            case let .performShowTag(tagName, currentSnapshot):
                performShowTag(tagName, currentSnapshot: currentSnapshot, state: &state)

            case let .prepareCollectionFileOpen(url, currentSnapshot):
                performPrepareCollectionFileOpen(url, currentSnapshot: currentSnapshot, state: &state)

            default:
                .none
            }
        }
    }

    private func performNavigateToPath(
        _ path: String,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
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
            shouldResetComposer: shouldRecordHistory,
        )
    }

    private func performShowRecents(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .recents = state.navigationState {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .recents

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performShowComputer(
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .computer = state.navigationState {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .computer

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performShowTag(
        _ tagName: String,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case let .tags(currentTagName) = state.navigationState,
           currentTagName == tagName
        {
            return .none
        }

        let previousNavigationState = state.navigationState
        state.appendBackHistory(currentSnapshot)
        state.forwardHistory = []
        state.navigationState = .tags(tagName)

        return directNavigationEffect(
            previousNavigationState: previousNavigationState,
            nextNavigationState: state.navigationState,
            shouldResetComposer: true,
        )
    }

    private func performPrepareCollectionFileOpen(
        _ url: URL,
        currentSnapshot: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) -> Effect<Action> {
        if case .collection = state.navigationState {
            return .none
        }

        let directoryPath = url.deletingLastPathComponent().path
        let previousSnapshot = ContentPageNavigationHistorySnapshot(
            navigationState: .folder(directoryPath),
            composerSnapshot: currentSnapshot.composerSnapshot,
        )
        state.appendBackHistory(previousSnapshot)
        state.forwardHistory = []
        return .none
    }

    private func directNavigationEffect(
        previousNavigationState: ContentPageNavigationRoute,
        nextNavigationState: ContentPageNavigationRoute,
        shouldResetComposer: Bool,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        if shouldResetComposer {
            effects.append(.send(.delegate(.resetComposer)))
        }

        effects.append(
            .send(.delegate(.logDAUNavigation(previous: previousNavigationState, next: nextNavigationState))),
        )
        effects.append(.send(.delegate(.navigateToState(nextNavigationState))))

        return .concatenate(effects)
    }
}

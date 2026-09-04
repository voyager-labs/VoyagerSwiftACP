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
                ContentPageNavigationDirectTransition.perform(.navigateToPath(path), state: &state)

            case .internal(.performShowRecents):
                ContentPageNavigationDirectTransition.perform(.showRecents, state: &state)

            case .internal(.performShowComputer):
                ContentPageNavigationDirectTransition.perform(.showComputer, state: &state)

            case let .internal(.performShowTag(tagName)):
                ContentPageNavigationDirectTransition.perform(.showTag(tagName), state: &state)

            case let .internal(.performShowAiChat(sessionID)):
                ContentPageNavigationDirectTransition.perform(.showAiChat(sessionID), state: &state)

            case let .internal(.performShowAiChatSessions(sessionID)):
                ContentPageNavigationDirectTransition.perform(.showAiChatSessions(sessionID), state: &state)

            case let .internal(.prepareCollectionFileOpen(url)):
                performPrepareCollectionFileOpen(url, state: &state)

            default:
                .none
            }
        }
    }

    private func performPrepareCollectionFileOpen(
        _: URL,
        state: inout State,
    ) -> Effect<Action> {
        if case .collection = state.navigationState {
            return .none
        }

        let previousSnapshot = state.makeContentPageNavigationHistorySnapshot()
        state.appendBackHistory(previousSnapshot)
        state.forwardHistory = []
        return .none
    }
}

import ComposableArchitecture
import VoyagerFeaturesAiChat

@Reducer
struct FileManagerInspectorFeature {
    typealias State = FileManagerInspectorState
    typealias Action = FileManagerInspectorAction

    var body: some Reducer<State, Action> {
        Scope(state: \.aiChat, action: \.aiChat) {
            AiChatFeature()
        }

        Reduce { state, action in
            switch action {
            case .toggleInspector:
                state.inspectorVisible.toggle()
                return .none

            case let .setInspectorVisible(isVisible):
                state.inspectorVisible = isVisible
                return .none

            case let .setInspectorPaneExists(exists):
                state.inspectorPaneExists = exists
                return .none

            case let .openChat(setup):
                state.inspectorVisible = true
                state.activeMode = .chat

                guard !state.aiChat.executionPhase.isProcessing else {
                    return .none
                }

                return .send(.aiChat(.setup(setup)))

            case .aiChat:
                return .none
            }
        }
    }
}

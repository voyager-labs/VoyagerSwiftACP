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

            case .closeChat:
                state.inspectorVisible = false
                return .none

            case let .openChat(setup, connectionsFile):
                state.inspectorVisible = true
                state.activeMode = .chat

                guard !state.aiChat.executionPhase.isProcessing else {
                    return .none
                }

                return .concatenate(
                    .send(.aiChat(.setup(setup))),
                    .send(.aiChat(.providerConnectionsUpdated(connectionsFile))),
                )

            case .aiChat(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case .delegate, .aiChat:
                return .none
            }
        }
    }
}

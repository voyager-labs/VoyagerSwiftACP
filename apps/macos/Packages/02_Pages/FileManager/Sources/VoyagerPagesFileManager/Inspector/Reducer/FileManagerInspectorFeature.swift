import ComposableArchitecture
import CoreGraphics
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat
import VoyagerShared

@Reducer
public struct FileManagerInspectorFeature {
    public typealias State = FileManagerInspectorState
    public typealias Action = FileManagerInspectorAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    public var body: some Reducer<State, Action> {
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

            case let .setInspectorWidth(width):
                let clampedWidth = max(FileManagerInspectorLayoutMetrics.minWidth, width)
                if abs(state.inspectorWidth - clampedWidth) < 0.5 {
                    return .none
                }
                state.inspectorWidth = clampedWidth
                userDefaultsClient.setDouble(clampedWidth, SettingsKeys.inspectorWidth)
                return .none

            case .closeChat:
                state.inspectorVisible = false
                return .none

            case .sessionHeaderNewChatTapped:
                return .send(.delegate(.newChatRequested))

            case .newChatRequested:
                state.inspectorVisible = true
                state.activeMode = .chat
                return .send(.aiChat(.prepareUnpersistedNewChat))

            case .sessionHeaderBackTapped, .showChatHistoryRequested:
                state.inspectorVisible = true
                state.activeMode = .chat
                return .send(.aiChat(.backToSessionsTapped))

            case let .openChat(setup, connectionsFile):
                return openChat(setup: setup, connectionsFile: connectionsFile, state: &state)

            case let .openNewChat(setup, connectionsFile):
                return .concatenate(
                    openChat(
                        setup: setup,
                        connectionsFile: connectionsFile,
                        state: &state,
                        presentInspector: false,
                    ),
                    .send(.aiChat(.prepareUnpersistedNewChat)),
                    .send(.setInspectorVisible(true)),
                )

            case let .openChatHistory(setup, connectionsFile):
                return .concatenate(
                    openChat(setup: setup, connectionsFile: connectionsFile, state: &state),
                    .send(.aiChat(.backToSessionsTapped)),
                )

            case .aiChat(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case let .aiChat(.delegate(.requestAttachmentPicker(originSessionID))):
                return .send(.delegate(.requestAttachmentPicker(originSessionID)))

            case .aiChat(.delegate(.clearCurrentContextSelection)):
                return .send(.delegate(.clearCurrentContextSelection))

            case .delegate, .aiChat:
                return .none
            }
        }
    }
}

private extension FileManagerInspectorFeature {
    func openChat(
        setup: AiChatSetupState,
        connectionsFile: AIConnectionsFile,
        state: inout State,
        presentInspector: Bool = true,
    ) -> Effect<Action> {
        state.inspectorVisible = presentInspector
        state.activeMode = .chat

        if let setupSessionID = setup.sessionID,
           state.aiChat.executionPhase.processingSessionID == setupSessionID
        {
            return .send(.aiChat(.providerConnectionsUpdated(connectionsFile)))
        }

        if let currentSessionID = state.aiChat.sessionID,
           let setupSessionID = setup.sessionID,
           currentSessionID == setupSessionID
        {
            return .send(.aiChat(.providerConnectionsUpdated(connectionsFile)))
        }

        return .concatenate(
            .send(.aiChat(.setup(setup))),
            .send(.aiChat(.providerConnectionsUpdated(connectionsFile))),
        )
    }
}

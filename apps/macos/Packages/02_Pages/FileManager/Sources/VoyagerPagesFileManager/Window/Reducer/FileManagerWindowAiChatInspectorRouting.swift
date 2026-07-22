import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

struct FileManagerAiChatInspectorOpenCancelID: Hashable {}

extension FileManagerWindowCommandRoutingReducer {
    func handleAiChatInspectorRequest(
        destination: FileManagerAiChatInspectorDestination,
        state: inout State,
    ) -> Effect<Action> {
        if isInspectorChatPresented(state, destination: destination) {
            state.pendingAiChatInspectorOpen = nil
            return .cancel(id: FileManagerAiChatInspectorOpenCancelID())
        }

        if isInspectorChatPresented(state) {
            state.pendingAiChatInspectorOpen = nil
            let destinationEffect: Effect<Action> = switch destination {
            case .newChat:
                .send(.inspector(.aiChat(.prepareUnpersistedNewChatWithContext(
                    FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state.content),
                ))))
            case .chatHistory:
                .send(.inspector(.showChatHistoryRequested))
            }
            return .concatenate(
                .cancel(id: FileManagerAiChatInspectorOpenCancelID()),
                destinationEffect,
            )
        }

        if let pendingOpen = state.pendingAiChatInspectorOpen,
           pendingOpen.destination == destination,
           pendingOpen.tabID == state.contentTabs.activeTabID
        {
            state.pendingAiChatInspectorOpen = nil
            return .cancel(id: FileManagerAiChatInspectorOpenCancelID())
        }

        return openAiChatInspectorEffect(state: &state, destination: destination)
    }

    func handleAiChatInspectorOpenCompletion(
        requestID: UUID,
        destination: FileManagerAiChatInspectorDestination,
        setup: AiChatSetupState,
        connectionsFile: AIConnectionsFile,
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingOpen = state.pendingAiChatInspectorOpen,
              pendingOpen.requestID == requestID,
              pendingOpen.destination == destination
        else { return .none }

        state.pendingAiChatInspectorOpen = nil
        guard state.contentTabs.activeTabID == pendingOpen.tabID,
              state.supportsInspector(tabID: pendingOpen.tabID)
        else { return .none }

        return switch destination {
        case .newChat:
            .send(.inspector(.openNewChat(setup, connectionsFile)))
        case .chatHistory:
            .send(.inspector(.openChatHistory(setup, connectionsFile)))
        }
    }

    private func isInspectorChatPresented(_ state: State) -> Bool {
        state.inspector.inspectorVisible && state.inspector.activeMode == .chat
    }

    private func isInspectorChatPresented(
        _ state: State,
        destination: FileManagerAiChatInspectorDestination,
    ) -> Bool {
        guard isInspectorChatPresented(state) else { return false }
        switch destination {
        case .newChat:
            return state.inspector.aiChat.isUntouchedPreparedTransientNewChat
        case .chatHistory:
            return state.inspector.aiChat.mode == .sessions
        }
    }

    private func openAiChatInspectorEffect(
        state: inout State,
        destination: FileManagerAiChatInspectorDestination,
    ) -> Effect<Action> {
        guard let activeTabID = state.contentTabs.activeTabID,
              state.supportsInspector(tabID: activeTabID)
        else {
            state.pendingAiChatInspectorOpen = nil
            return .cancel(id: FileManagerAiChatInspectorOpenCancelID())
        }

        let requestID = uuid()
        state.pendingAiChatInspectorOpen = FileManagerPendingAiChatInspectorOpen(
            requestID: requestID,
            tabID: activeTabID,
            destination: destination,
        )
        var setup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: state.content)
        switch destination {
        case .newChat:
            setup.mode = .chat
        case .chatHistory:
            setup.mode = .sessions
        }
        return .run { [aiConnectionsFileClient, setup] send in
            let connectionsFile: AIConnectionsFile
            do {
                connectionsFile = try await aiConnectionsFileClient.load()
            } catch {
                connectionsFile = .empty()
            }

            switch destination {
            case .newChat:
                await send(.internal(.aiChatNewChatInspectorOpenLoaded(
                    requestID: requestID,
                    setup: setup,
                    connectionsFile: connectionsFile,
                )))
            case .chatHistory:
                await send(.internal(.aiChatHistoryInspectorOpenLoaded(
                    requestID: requestID,
                    setup: setup,
                    connectionsFile: connectionsFile,
                )))
            }
        }
        .cancellable(id: FileManagerAiChatInspectorOpenCancelID(), cancelInFlight: true)
    }
}

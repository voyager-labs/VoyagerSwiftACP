import ComposableArchitecture
import VoyagerEntitiesAi

extension AiChatFeature {
    func recoverFromError(state: inout State) -> Effect<Action> {
        switch state.executionPhase {
        case let .persistenceRecovery(lock, _):
            return retryPersistenceRecovery(lock: lock, state: state)
        case .failed:
            return startRequest(kind: .regenerate, state: &state)
        case .completed, .cancelled, .idle, .processing:
            break
        }

        if state.sessionStatus == .failed, let restoreSessionID = state.restoreSessionID {
            state.sessionStatus = .restoring
            return restoreSession(sessionID: restoreSessionID, state: state)
        }

        if state.sessionStatus == .rebindRequired {
            return .send(.delegate(.openAISettings))
        }

        if state.lastExecutionFailure != nil {
            return startRequest(kind: .regenerate, state: &state)
        }

        return .none
    }

    private func retryPersistenceRecovery(lock: AiChatRequestLock, state: State) -> Effect<Action> {
        let snapshot = makeSessionSnapshot(state: state, lock: lock)
        return .run { [aiChatSessionPersistenceClient] send in
            do {
                try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.persistenceRecoverySucceeded(lock))
            } catch {
                await send(.persistenceRecoveryRetryFailed(lock, .unknown))
            }
        }
        .cancellable(id: CancelID.persistenceRecovery, cancelInFlight: true)
    }
}

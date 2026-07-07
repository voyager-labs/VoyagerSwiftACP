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

        if state.lastExecutionFailure != nil {
            return startRequest(kind: .regenerate, state: &state)
        }

        return .none
    }

    private func retryPersistenceRecovery(lock: AiChatRequestLock, state: State) -> Effect<Action> {
        let snapshot = persistenceRecoverySnapshot(for: lock, state: state)
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

    func handlePersistenceFailed(lock: AiChatRequestLock, failure: AiChatExecutionFailure, state: inout State)
        -> Effect<Action>
    {
        switch state.executionPhase {
        case let .completed(currentLock):
            guard currentLock.requestID == lock.requestID else { return .none }
            state.executionPhase = .persistenceRecovery(lock, failure)
            state.lastExecutionFailure = failure
            return .none

        case let .persistenceRecovery(currentLock, _):
            guard currentLock.requestID == lock.requestID else { return .none }
            state.executionPhase = .persistenceRecovery(lock, failure)
            state.lastExecutionFailure = failure
            return .none

        default:
            guard let backgroundPhase = state.backgroundExecutionPhases[lock.requestID],
                  let backgroundLock = backgroundPhase.lock,
                  backgroundLock.runID == lock.runID
            else { return .none }
            state.backgroundExecutionPhases[lock.requestID] = .persistenceRecovery(lock, failure)
            return .none
        }
    }

    func handlePersistenceRecoverySucceeded(lock: AiChatRequestLock, state: inout State) -> Effect<Action> {
        guard case let .persistenceRecovery(currentLock, _) = state.executionPhase,
              currentLock.requestID == lock.requestID
        else { return .none }
        state.executionPhase = .completed(lock)
        state.lastExecutionFailure = nil
        return .none
    }

    func handlePersistenceRecoveryRetryFailed(
        lock: AiChatRequestLock,
        failure: AiChatExecutionFailure,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .persistenceRecovery(currentLock, _) = state.executionPhase,
              currentLock.requestID == lock.requestID
        else { return .none }
        state.executionPhase = .persistenceRecovery(lock, failure)
        state.lastExecutionFailure = failure
        return .none
    }

    private func persistenceRecoverySnapshot(for lock: AiChatRequestLock, state: State) -> AiChatSessionSnapshot {
        lock.finalSnapshot ?? makeSessionSnapshot(
            state: state,
            lock: lock,
            updatedAtMs: lock.observabilitySummary.terminalAtMs ?? currentTimestampMs(),
        )
    }
}

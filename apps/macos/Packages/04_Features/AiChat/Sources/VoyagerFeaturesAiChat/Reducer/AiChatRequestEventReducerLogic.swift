import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    func handleExecutionEvent(_ event: AiChatEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .started(context):
            handleStartedEvent(context, state: &state)
        case let .delta(context, text):
            handleDeltaEvent(context: context, text: text, state: &state)
        case let .final(response):
            handleFinalEvent(response, state: &state)
        case let .failed(context, reason):
            handleFailedEvent(context: context, reason: reason, state: &state)
        }
    }

    private func handleStartedEvent(_ context: AiChatRequestContextSnapshot, state: inout State) -> Effect<Action> {
        guard case let .processing(lock) = state.executionPhase,
              matches(lock: lock, context: context)
        else {
            return .none
        }
        return .none
    }

    private func handleDeltaEvent(
        context: AiChatRequestContextSnapshot,
        text: String,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .processing(lock) = state.executionPhase,
              matches(lock: lock, context: context)
        else {
            return .none
        }
        state.streamingAssistantDraft = (state.streamingAssistantDraft ?? "") + text
        state.executionPhase = .processing(lock.recordingDelta(at: currentTimestampMs()))
        state.transcriptAutoScrollVersion += 1
        return .none
    }

    private func handleFinalEvent(_ response: AiChatResponse, state: inout State) -> Effect<Action> {
        guard case let .processing(lock) = state.executionPhase,
              matches(lock: lock, context: response.context)
        else {
            return .none
        }

        let terminalTimestampMs = currentTimestampMs()
        state.streamingAssistantDraft = nil
        let normalizedResponse = AiChatResponse(
            context: response.context,
            assistantMessage: response.assistantMessage,
            completedAtMs: terminalTimestampMs,
        )
        let finalizedLock = lock.recordingTerminal(at: terminalTimestampMs, failure: nil, wasCancelled: false)
        applyFinal(response: normalizedResponse, lock: finalizedLock, state: &state)
        let snapshot = makeSessionSnapshot(state: state, lock: finalizedLock, updatedAtMs: terminalTimestampMs)
        return saveFinalSnapshot(snapshot, finalizedLock: finalizedLock)
    }

    private func saveFinalSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        finalizedLock: AiChatRequestLock,
    ) -> Effect<Action> {
        .merge(
            .run { [aiChatSessionPersistenceClient] send in
                do {
                    try await aiChatSessionPersistenceClient.saveSession(snapshot)
                    await send(.sessionSnapshotSaved(AiChatSessionSummary(snapshot: snapshot)))
                } catch {
                    await send(.persistenceFailed(finalizedLock, .unknown))
                }
            },
            .cancel(id: CancelID.request),
        )
    }

    private func handleFailedEvent(
        context: AiChatRequestContextSnapshot,
        reason: AiChatExecutionFailure,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .processing(lock) = state.executionPhase,
              matches(lock: lock, context: context)
        else {
            return .none
        }

        clearStreamingDraftIfEmpty(lock: lock, state: &state)
        state.lockedModelHandle = nil
        state.lastExecutionFailure = reason
        state.executionPhase = .failed(
            lock.recordingTerminal(at: currentTimestampMs(), failure: reason, wasCancelled: false),
            reason,
        )
        state.transcriptAutoScrollVersion += 1
        return .cancel(id: CancelID.request)
    }

    private func clearStreamingDraftIfEmpty(lock: AiChatRequestLock, state: inout State) {
        let hasStreamingDraft = (state.streamingAssistantDraft?.isEmpty == false)
            || lock.observabilitySummary.chunkCount > 0
        if !hasStreamingDraft {
            state.streamingAssistantDraft = nil
        }
    }
}

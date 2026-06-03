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
        let updatedLock = lock.recordingDelta(at: currentTimestampMs())
        state.executionPhase = .processing(updatedLock)
        guard isVisibleRequest(lock: lock, state: state) else {
            return .none
        }
        state.streamingAssistantDraft = (state.streamingAssistantDraft ?? "") + text
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
        let snapshot: AiChatSessionSnapshot
        if isVisibleRequest(lock: lock, state: state) {
            applyFinal(response: normalizedResponse, lock: finalizedLock, state: &state)
            snapshot = makeSessionSnapshot(state: state, lock: finalizedLock, updatedAtMs: terminalTimestampMs)
        } else {
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(finalizedLock)
            snapshot = makeOffscreenFinalSnapshot(
                response: normalizedResponse,
                lock: finalizedLock,
                updatedAtMs: terminalTimestampMs,
            )
        }
        return saveFinalSnapshot(snapshot, finalizedLock: finalizedLock)
    }

    private func isVisibleRequest(lock: AiChatRequestLock, state: State) -> Bool {
        state.sessionID == lock.context.sessionID
    }

    private func makeOffscreenFinalSnapshot(
        response: AiChatResponse,
        lock: AiChatRequestLock,
        updatedAtMs: Int64,
    ) -> AiChatSessionSnapshot {
        var transcriptHistory = lock.request.messages
        if let index = lock.assistantReplacementIndex,
           transcriptHistory.indices.contains(index),
           transcriptHistory[index].role == .assistant
        {
            transcriptHistory[index] = response.assistantMessage
        } else {
            transcriptHistory.append(response.assistantMessage)
        }

        guard let sessionID = lock.context.sessionID else {
            preconditionFailure("Missing session ID for offscreen finalized request")
        }
        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: lock.context.provider,
            model: lock.context.model,
            selectedModelRow: lock.selectedModelRow,
            selectedThinking: lock.context.selectedThinking,
            transcriptHistory: transcriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: persistenceSafeRequestContext(lock.context.requestContext),
            updatedAtMs: updatedAtMs,
        )
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
                } catch is CancellationError {
                    return
                } catch {
                    await send(.persistenceFailed(finalizedLock, .unknown))
                }
            }
            .cancellable(id: CancelID.requestFinalPersistence, cancelInFlight: true),
            .cancel(id: CancelID.request),
            .cancel(id: CancelID.requestStartPersistence),
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
        return .merge(
            .cancel(id: CancelID.request),
            .cancel(id: CancelID.requestStartPersistence),
        )
    }

    private func clearStreamingDraftIfEmpty(lock: AiChatRequestLock, state: inout State) {
        let hasStreamingDraft = (state.streamingAssistantDraft?.isEmpty == false)
            || lock.observabilitySummary.chunkCount > 0
        if !hasStreamingDraft {
            state.streamingAssistantDraft = nil
        }
    }
}

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
        guard processingLock(matching: context, state: state) != nil else { return .none }
        return .none
    }

    private func handleDeltaEvent(
        context: AiChatRequestContextSnapshot,
        text: String,
        state: inout State,
    ) -> Effect<Action> {
        guard let matched = processingLock(matching: context, state: state) else { return .none }
        let updatedLock = matched.lock.recordingDelta(at: currentTimestampMs())
        if matched.isBackground {
            state.backgroundExecutionPhases[updatedLock.requestID] = .processing(updatedLock)
            return .none
        }

        state.executionPhase = .processing(updatedLock)
        guard isVisibleRequest(lock: updatedLock, state: state) else { return .none }
        state.streamingAssistantDraft = (state.streamingAssistantDraft ?? "") + text
        state.transcriptAutoScrollVersion += 1
        return .none
    }

    private func handleFinalEvent(_ response: AiChatResponse, state: inout State) -> Effect<Action> {
        guard let matched = processingLock(matching: response.context, state: state) else { return .none }

        let terminalTimestampMs = currentTimestampMs()
        let normalizedResponse = AiChatResponse(
            context: response.context,
            assistantMessage: response.assistantMessage,
            completedAtMs: terminalTimestampMs,
        )
        let finalizedLock = matched.lock.recordingTerminal(at: terminalTimestampMs, failure: nil, wasCancelled: false)
        let snapshot: AiChatSessionSnapshot
        if matched.isBackground {
            snapshot = makeOffscreenFinalSnapshot(
                response: normalizedResponse,
                lock: finalizedLock,
                updatedAtMs: terminalTimestampMs,
            )
            let finalizedLockWithSnapshot = finalizedLock.recordingFinalSnapshot(snapshot)
            state.backgroundExecutionPhases[finalizedLock.requestID] = .completed(finalizedLockWithSnapshot)
        } else if isVisibleRequest(lock: finalizedLock, state: state) {
            state.streamingAssistantDraft = nil
            applyFinal(response: normalizedResponse, lock: finalizedLock, state: &state)
            snapshot = makeSessionSnapshot(state: state, lock: finalizedLock, updatedAtMs: terminalTimestampMs)
            state.executionPhase = .completed(finalizedLock.recordingFinalSnapshot(snapshot))
        } else {
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            snapshot = makeOffscreenFinalSnapshot(
                response: normalizedResponse,
                lock: finalizedLock,
                updatedAtMs: terminalTimestampMs,
            )
            state.executionPhase = .completed(finalizedLock.recordingFinalSnapshot(snapshot))
        }
        return saveFinalSnapshot(snapshot, finalizedLock: finalizedLock.recordingFinalSnapshot(snapshot))
    }

    private func processingLock(
        matching context: AiChatRequestContextSnapshot,
        state: State,
    ) -> (lock: AiChatRequestLock, isBackground: Bool)? {
        if case let .processing(lock) = state.executionPhase, matches(lock: lock, context: context) {
            return (lock, false)
        }
        if case let .processing(lock) = state.backgroundExecutionPhases[context.requestID],
           matches(lock: lock, context: context)
        {
            return (lock, true)
        }
        return nil
    }

    private func isVisibleRequest(lock: AiChatRequestLock, state: State) -> Bool {
        state.sessionID == lock.context.sessionID
    }

    private func makeOffscreenFinalSnapshot(
        response: AiChatResponse,
        lock: AiChatRequestLock,
        updatedAtMs: Int64,
    ) -> AiChatSessionSnapshot {
        var transcriptHistory = lock.persistenceTranscriptHistory
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
            customTitle: lock.customTitle,
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
                    let persistedSnapshot = try await aiChatSessionPersistenceClient.saveSession(snapshot)
                    await send(.sessionSnapshotSaved(
                        AiChatSessionSummary(snapshot: persistedSnapshot),
                        snapshot: persistedSnapshot,
                        requestID: finalizedLock.requestID,
                        runID: finalizedLock.runID,
                    ))
                } catch is CancellationError {
                    return
                } catch {
                    await send(.persistenceFailed(finalizedLock, .unknown))
                }
            }
            .cancellable(id: CancelID.requestFinalPersistence(finalizedLock.requestID), cancelInFlight: true),
            .cancel(id: CancelID.request(finalizedLock.requestID)),
            .cancel(id: CancelID.requestStartPersistence(finalizedLock.requestID)),
        )
    }

    private func handleFailedEvent(
        context: AiChatRequestContextSnapshot,
        reason: AiChatExecutionFailure,
        state: inout State,
    ) -> Effect<Action> {
        guard let matched = processingLock(matching: context, state: state) else { return .none }

        let failedLock = matched.lock.recordingTerminal(
            at: currentTimestampMs(),
            failure: reason,
            wasCancelled: false,
        )
        if matched.isBackground {
            state.backgroundExecutionPhases[failedLock.requestID] = .failed(failedLock, reason)
            return .merge(
                .cancel(id: CancelID.request(failedLock.requestID)),
                .cancel(id: CancelID.requestStartPersistence(failedLock.requestID)),
            )
        }

        state.executionPhase = .failed(failedLock, reason)
        guard isVisibleRequest(lock: failedLock, state: state) else {
            state.lockedModelHandle = nil
            return .merge(
                .cancel(id: CancelID.request(failedLock.requestID)),
                .cancel(id: CancelID.requestStartPersistence(failedLock.requestID)),
            )
        }

        clearStreamingDraftIfEmpty(lock: failedLock, state: &state)
        state.lockedModelHandle = nil
        state.lastExecutionFailure = reason
        state.transcriptAutoScrollVersion += 1
        return .merge(
            .cancel(id: CancelID.request(failedLock.requestID)),
            .cancel(id: CancelID.requestStartPersistence(failedLock.requestID)),
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

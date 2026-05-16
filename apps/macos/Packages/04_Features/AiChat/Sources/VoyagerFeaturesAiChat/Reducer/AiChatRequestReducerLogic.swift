import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

struct AiChatPreparedRequest {
    var prompt: String
    var messages: [AiChatMessage]
    var assistantReplacementIndex: Int?
}

extension AiChatFeature {
    func applyMissingSelectedModel(_ missingHandle: AiModelHandle, to state: inout State) {
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.unavailableSelectedModelHandle = missingHandle
    }

    func clearRetryBlockingFailureIfNeeded(_ state: inout State) {
        state.lastExecutionFailure = nil

        switch state.executionPhase {
        case .failed, .persistenceRecovery:
            state.executionPhase = .idle
        default:
            break
        }
    }

    func startRequest(kind: AiChatRequestKind, state: inout State) -> Effect<Action> {
        guard !state.isProcessing,
              let sessionID = state.sessionID,
              case let .loaded(models) = state.modelListState,
              let selectedModel = state.resolvedModel(for: state.selectedModelHandle, in: models),
              let preparedRequest = prepareRequest(kind: kind, state: state)
        else { return .none }

        let selectedHandle = selectedModel.id
        let lock = makeRequestLock(
            kind: kind,
            sessionID: sessionID,
            selectedModel: selectedModel,
            selectedRow: resolvedSelectedModelRow(in: state),
            preparedRequest: preparedRequest,
            state: state,
        )

        applyRequestStart(
            kind: kind,
            prompt: preparedRequest.prompt,
            selectedHandle: selectedHandle,
            lock: lock,
            state: &state,
        )
        return execute(request: lock.request)
    }

    private func prepareRequest(kind: AiChatRequestKind, state: State) -> AiChatPreparedRequest? {
        switch kind {
        case .submit:
            prepareSubmitRequest(state: state)
        case .regenerate:
            prepareRegenerateRequest(state: state)
        }
    }

    private func prepareSubmitRequest(state: State) -> AiChatPreparedRequest? {
        let trimmed = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return AiChatPreparedRequest(
            prompt: trimmed,
            messages: state.transcriptHistory + [AiChatMessage(role: .user, content: trimmed)],
            assistantReplacementIndex: nil,
        )
    }

    private func prepareRegenerateRequest(state: State) -> AiChatPreparedRequest? {
        guard let lastUserPrompt = lastUserPrompt(in: state.transcriptHistory) else { return nil }

        if state.transcriptHistory.last?.role == .assistant {
            return AiChatPreparedRequest(
                prompt: lastUserPrompt,
                messages: Array(state.transcriptHistory.dropLast()),
                assistantReplacementIndex: state.transcriptHistory.count - 1,
            )
        }

        return AiChatPreparedRequest(
            prompt: lastUserPrompt,
            messages: state.transcriptHistory,
            assistantReplacementIndex: nil,
        )
    }

    private func makeRequestLock(
        kind: AiChatRequestKind,
        sessionID: AiChatSessionID,
        selectedModel: AiProviderModel,
        selectedRow: AiModelCatalogRow?,
        preparedRequest: AiChatPreparedRequest,
        state: State,
    ) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let selectedHandle = selectedModel.id
        let context = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModel: selectedModel,
            selectedModelRow: selectedRow,
            selectedThinking: state.selectedThinking,
            sessionStatus: .active,
            currentContext: state.currentContext,
            promptSummary: preparedRequest.prompt,
            submittedAtMs: nil,
        )
        let request = AiChatRequest(context: context, messages: preparedRequest.messages)

        return AiChatRequestLock(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: selectedRow,
            assistantReplacementIndex: preparedRequest.assistantReplacementIndex,
        )
    }

    private func applyRequestStart(
        kind: AiChatRequestKind,
        prompt: String,
        selectedHandle: AiModelHandle,
        lock: AiChatRequestLock,
        state: inout State,
    ) {
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.executionPhase = .processing(lock)
        state.sessionStatus = .active

        if kind == .submit {
            state.transcriptHistory.append(AiChatMessage(role: .user, content: prompt))
            state.draftText = ""
        }
    }

    private func execute(request: AiChatRequest) -> Effect<Action> {
        .run { [aiChatExecutionClient] send in
            for await event in aiChatExecutionClient.execute(request) {
                await send(.executionEvent(event))
            }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    func handleExecutionEvent(_ event: AiChatEvent, state: inout State) -> Effect<Action> {
        switch event {
        case .started:
            return .none

        case let .final(response):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: response.context)
            else {
                return .none
            }

            applyFinal(response: response, lock: lock, state: &state)
            let snapshot = makeSessionSnapshot(state: state, lock: lock)

            return .merge(
                .run { [aiChatSessionPersistenceClient] send in
                    do {
                        try await aiChatSessionPersistenceClient.saveSession(snapshot)
                    } catch {
                        await send(.persistenceFailed(lock, .unknown))
                    }
                },
                .cancel(id: CancelID.request),
            )

        case let .failed(context, reason):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }

            state.lockedModelHandle = nil
            state.lastExecutionFailure = reason
            state.executionPhase = .failed(lock, reason)
            return .cancel(id: CancelID.request)
        }
    }

    func applyFinal(response: AiChatResponse, lock: AiChatRequestLock, state: inout State) {
        if let index = lock.assistantReplacementIndex,
           state.transcriptHistory.indices.contains(index),
           state.transcriptHistory[index].role == .assistant
        {
            state.transcriptHistory[index] = response.assistantMessage
        } else {
            state.transcriptHistory.append(response.assistantMessage)
        }

        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .completed(lock)
    }

    func makeSessionSnapshot(state: State, lock: AiChatRequestLock) -> AiChatSessionSnapshot {
        guard let sessionID = lock.context.sessionID ?? state.sessionID else {
            preconditionFailure("Missing session ID for finalized request")
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: state.sessionStatus,
            provider: lock.context.provider,
            model: lock.context.model,
            selectedModelRow: lock.selectedModelRow,
            selectedThinking: lock.context.selectedThinking,
            transcriptHistory: state.transcriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            updatedAtMs: 0,
        )
    }

    private func matches(lock: AiChatRequestLock, context: AiChatRequestContextSnapshot) -> Bool {
        lock.requestID == context.requestID && lock.runID == context.runID
    }

    private func lastUserPrompt(in transcriptHistory: [AiChatMessage]) -> String? {
        transcriptHistory.reversed().first(where: { $0.role == .user })?.content
    }

    func normalizeSelectionIfNeeded(_ state: inout State) {
        switch state.modelListState {
        case let .loaded(models):
            let previousSelection = state.selectedModelHandle
            state.selectedModelHandle = state.normalizedSelectionHandle(state.selectedModelHandle, in: models)
            if let previousSelection, state.selectedModelHandle == nil {
                applyMissingSelectedModel(previousSelection, to: &state)
            } else if state.selectedModelHandle != nil {
                state.unavailableSelectedModelHandle = nil
            }
            state.selectedThinking = State.normalizeSelectedThinking(state.selectedThinking, for: state.resolvedSelectedModel)

        case .empty:
            if let previousSelection = state.selectedModelHandle {
                applyMissingSelectedModel(previousSelection, to: &state)
            }

        case .idle, .loading, .failed:
            if state.selectedModelHandle != nil {
                state.selectedThinking = State.normalizeSelectedThinking(state.selectedThinking, for: state.resolvedSelectedModel)
            }
        }
    }

    func resolvedSelectionHandle(_ handle: AiModelHandle?, in models: [AiProviderModel]) -> AiModelHandle? {
        State.normalizedSelectionHandle(handle, in: models)
    }

    func resolvedSelectedModelRow(in state: State) -> AiModelCatalogRow? {
        state.resolvedModelRow(for: state.selectedModelHandle)
    }
}

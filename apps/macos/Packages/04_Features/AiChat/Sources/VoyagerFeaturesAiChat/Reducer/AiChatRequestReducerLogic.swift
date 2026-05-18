import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

let kAiChatHistoryCharacterBudget = 24000

struct AiChatPreparedRequest {
    var prompt: String
    var messages: [AiChatMessage]
    var assistantReplacementIndex: Int?
    var historyTruncation: AiChatHistoryTruncationMetadata
    var requestContextOverride: AiChatLockedRequestContextSnapshot? = nil
}

struct AiChatRequestLockInput {
    var kind: AiChatRequestKind
    var sessionID: AiChatSessionID
    var selectedModel: AiProviderModel
    var selectedRow: AiModelCatalogRow?
    var preparedRequest: AiChatPreparedRequest
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
            input: AiChatRequestLockInput(
                kind: kind,
                sessionID: sessionID,
                selectedModel: selectedModel,
                selectedRow: resolvedSelectedModelRow(in: state),
                preparedRequest: preparedRequest,
            ),
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

        let fullMessages = state.transcriptHistory + [AiChatMessage(role: .user, content: trimmed)]
        let truncatedHistory = truncateHistory(fullMessages, currentUserMessage: trimmed)

        return AiChatPreparedRequest(
            prompt: trimmed,
            messages: truncatedHistory.messages,
            assistantReplacementIndex: nil,
            historyTruncation: truncatedHistory.metadata,
        )
    }

    private func prepareRegenerateRequest(state: State) -> AiChatPreparedRequest? {
        guard let lastUserPrompt = lastUserPrompt(in: state.transcriptHistory) else { return nil }

        let messages: [AiChatMessage]
        let assistantReplacementIndex: Int?
        if state.transcriptHistory.last?.role == .assistant {
            messages = Array(state.transcriptHistory.dropLast())
            assistantReplacementIndex = state.transcriptHistory.count - 1
        } else {
            messages = state.transcriptHistory
            assistantReplacementIndex = nil
        }

        let truncatedHistory = truncateHistory(messages, currentUserMessage: lastUserPrompt)

        return AiChatPreparedRequest(
            prompt: lastUserPrompt,
            messages: truncatedHistory.messages,
            assistantReplacementIndex: assistantReplacementIndex,
            historyTruncation: truncatedHistory.metadata,
            requestContextOverride: lastSubmittedRequestContext(in: state)
        )
    }

    private func makeRequestLock(input: AiChatRequestLockInput, state: State) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let submittedAtMs = currentTimestampMs()
        let selectedHandle = input.selectedModel.id
        let lockedRequestContext = input.preparedRequest.requestContextOverride ??
            makeLockedRequestContextSnapshot(state: state)
        let context = AiChatRequestContextSnapshot(
            sessionID: input.sessionID,
            requestID: requestID,
            runID: runID,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModel: input.selectedModel,
            selectedModelRow: input.selectedRow,
            selectedThinking: state.selectedThinking,
            sessionStatus: .active,
            currentContext: lockedRequestContext.currentContext,
            requestContext: lockedRequestContext,
            promptSummary: input.preparedRequest.prompt,
            submittedAtMs: submittedAtMs,
        )
        let request = AiChatRequest(context: context, messages: input.preparedRequest.messages)

        return AiChatRequestLock(
            kind: input.kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: input.selectedRow,
            assistantReplacementIndex: input.preparedRequest.assistantReplacementIndex,
            historyTruncation: input.preparedRequest.historyTruncation,
            observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: submittedAtMs),
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
        state.streamingAssistantDraft = nil
        state.executionPhase = .processing(lock)
        state.sessionStatus = .active

        if kind == .submit {
            state.transcriptHistory.append(AiChatMessage(role: .user, content: prompt))
            state.draftText = ""
        }
    }

    private func execute(request: AiChatRequest) -> Effect<Action> {
        .run { [aiChatExecutionClient, aiConnectionsFileClient] send in
            let credential: StoredCredentialPayload?
            do {
                let connectionsFile = try await aiConnectionsFileClient.load()
                credential = Self.executionCredential(for: request.context.provider, in: connectionsFile)
            } catch {
                await send(.executionEvent(.failed(context: request.context, reason: .unknown)))
                return
            }

            for await event in aiChatExecutionClient.execute(request, credential) {
                await send(.executionEvent(event))
            }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    func applyFinal(response: AiChatResponse, lock: AiChatRequestLock, state: inout State) {
        state.streamingAssistantDraft = nil
        if let index = lock.assistantReplacementIndex,
           state.transcriptHistory.indices.contains(index),
           state.transcriptHistory[index].role == .assistant {
            state.transcriptHistory[index] = response.assistantMessage
        } else {
            state.transcriptHistory.append(response.assistantMessage)
        }

        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .completed(lock)
    }

    func makeSessionSnapshot(
        state: State,
        lock: AiChatRequestLock,
        updatedAtMs: Int64? = nil,
    ) -> AiChatSessionSnapshot {
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
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: updatedAtMs ?? lock.observabilitySummary.terminalAtMs ?? lock.context.submittedAtMs ?? 0,
        )
    }

    func matches(lock: AiChatRequestLock, context: AiChatRequestContextSnapshot) -> Bool {
        lock.requestID == context.requestID && lock.runID == context.runID
    }

    private static func executionCredential(
        for provider: AiProvider,
        in file: AIConnectionsFile,
    ) -> StoredCredentialPayload? {
        guard let record = file.providers[provider.rawValue],
              record.snapshot.lastKnownStatus == .connected
        else { return nil }
        return record.credential
    }

    private func lastUserPrompt(in transcriptHistory: [AiChatMessage]) -> String? {
        transcriptHistory.reversed().first(where: { $0.role == .user })?.content
    }

    private func lastSubmittedRequestContext(in state: State) -> AiChatLockedRequestContextSnapshot? {
        state.executionPhase.lock?.context.requestContext ?? state.lastRequestContext
    }

    private func makeLockedRequestContextSnapshot(state: State) -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: state.currentContext,
            addedAttachments: aiChatAttachmentResolverClient.resolve(state.addedAttachments)
        )
    }

    func currentTimestampMs() -> Int64 {
        Int64(date().timeIntervalSince1970 * 1000)
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
            state.selectedThinking = State.normalizeSelectedThinking(
                state.selectedThinking,
                for: state.resolvedSelectedModel,
            )

        case .empty:
            if let previousSelection = state.selectedModelHandle {
                applyMissingSelectedModel(previousSelection, to: &state)
            }

        case .idle, .loading, .failed:
            if state.selectedModelHandle != nil {
                state.selectedThinking = State.normalizeSelectedThinking(
                    state.selectedThinking,
                    for: state.resolvedSelectedModel,
                )
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

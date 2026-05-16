import ComposableArchitecture
import Foundation
// swiftlint:disable file_length
import VoyagerEntitiesAi

private let kAiChatHistoryCharacterBudget = 24000

struct AiChatPreparedRequest {
    var prompt: String
    var messages: [AiChatMessage]
    var assistantReplacementIndex: Int?
    var historyTruncation: AiChatHistoryTruncationMetadata
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
            state: state
        )

        applyRequestStart(
            kind: kind,
            prompt: preparedRequest.prompt,
            selectedHandle: selectedHandle,
            lock: lock,
            state: &state
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
            historyTruncation: truncatedHistory.metadata
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
            historyTruncation: truncatedHistory.metadata
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func makeRequestLock(
        kind: AiChatRequestKind,
        sessionID: AiChatSessionID,
        selectedModel: AiProviderModel,
        selectedRow: AiModelCatalogRow?,
        preparedRequest: AiChatPreparedRequest,
        state: State
    ) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let submittedAtMs = currentTimestampMs()
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
            submittedAtMs: submittedAtMs
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
            historyTruncation: preparedRequest.historyTruncation,
            observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: submittedAtMs)
        )
    }

    private func applyRequestStart(
        kind: AiChatRequestKind,
        prompt: String,
        selectedHandle: AiModelHandle,
        lock: AiChatRequestLock,
        state: inout State
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
                credential = nil
            }

            for await event in aiChatExecutionClient.execute(request, credential) {
                await send(.executionEvent(event))
            }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    // swiftlint:disable:next function_body_length
    func handleExecutionEvent(_ event: AiChatEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .started(context):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }
            return .none

        case let .delta(context, text):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }
            state.streamingAssistantDraft = (state.streamingAssistantDraft ?? "") + text
            state.executionPhase = .processing(lock.recordingDelta(at: currentTimestampMs()))
            return .none

        case let .final(response):
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
                completedAtMs: terminalTimestampMs
            )
            let finalizedLock = lock.recordingTerminal(at: terminalTimestampMs, failure: nil, wasCancelled: false)
            applyFinal(response: normalizedResponse, lock: finalizedLock, state: &state)
            let snapshot = makeSessionSnapshot(state: state, lock: finalizedLock, updatedAtMs: terminalTimestampMs)

            return .merge(
                .run { [aiChatSessionPersistenceClient] send in
                    do {
                        try await aiChatSessionPersistenceClient.saveSession(snapshot)
                    } catch {
                        await send(.persistenceFailed(finalizedLock, .unknown))
                    }
                },
                .cancel(id: CancelID.request)
            )

        case let .failed(context, reason):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }

            let hasStreamingDraft = (state.streamingAssistantDraft?.isEmpty == false)
                || lock.observabilitySummary.chunkCount > 0
            if !hasStreamingDraft {
                state.streamingAssistantDraft = nil
            }
            state.lockedModelHandle = nil
            state.lastExecutionFailure = reason
            state.executionPhase = .failed(
                lock.recordingTerminal(at: currentTimestampMs(), failure: reason, wasCancelled: false),
                reason
            )
            return .cancel(id: CancelID.request)
        }
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
        updatedAtMs: Int64? = nil
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
            updatedAtMs: updatedAtMs ?? lock.observabilitySummary.terminalAtMs ?? lock.context.submittedAtMs ?? 0
        )
    }

    private func matches(lock: AiChatRequestLock, context: AiChatRequestContextSnapshot) -> Bool {
        lock.requestID == context.requestID && lock.runID == context.runID
    }

    private static func executionCredential(
        for provider: AiProvider,
        in file: AIConnectionsFile
    ) -> StoredCredentialPayload? {
        guard let record = file.providers[provider.rawValue],
              record.snapshot.lastKnownStatus == .connected
        else { return nil }
        return record.credential
    }

    private func lastUserPrompt(in transcriptHistory: [AiChatMessage]) -> String? {
        transcriptHistory.reversed().first(where: { $0.role == .user })?.content
    }

    func currentTimestampMs() -> Int64 {
        Int64(date().timeIntervalSince1970 * 1000)
    }

    private func truncateHistory(
        _ messages: [AiChatMessage],
        currentUserMessage: String,
        budget: Int = kAiChatHistoryCharacterBudget
    ) -> (messages: [AiChatMessage], metadata: AiChatHistoryTruncationMetadata) {
        guard !messages.isEmpty else {
            return (
                [],
                AiChatHistoryTruncationMetadata(
                    includedMessageCount: 0,
                    excludedMessageCount: 0,
                    budget: budget,
                    truncationReason: nil
                )
            )
        }

        let currentUserIndex = messages.lastIndex { $0.role == .user && $0.content == currentUserMessage }
            ?? messages.lastIndex(where: { $0.role == .user })
            ?? messages.index(before: messages.endIndex)

        let protectedMessages = Array(messages[currentUserIndex...])
        var includedMessages = protectedMessages
        var usedCharacters = protectedMessages.reduce(0) { $0 + $1.content.count }

        var chunks: [[AiChatMessage]] = []
        var index = messages.startIndex
        while index < currentUserIndex {
            let message = messages[index]
            if message.role == .user,
               messages.index(after: index) < currentUserIndex,
               messages[messages.index(after: index)].role == .assistant {
                let assistantIndex = messages.index(after: index)
                chunks.append([message, messages[assistantIndex]])
                index = messages.index(after: assistantIndex)
            } else {
                chunks.append([message])
                index = messages.index(after: index)
            }
        }

        for chunk in chunks.reversed() {
            let chunkCharacters = chunk.reduce(0) { $0 + $1.content.count }
            if usedCharacters + chunkCharacters > budget {
                continue
            }
            includedMessages.insert(contentsOf: chunk, at: 0)
            usedCharacters += chunkCharacters
        }

        let excludedMessageCount = messages.count - includedMessages.count
        return (
            includedMessages,
            AiChatHistoryTruncationMetadata(
                includedMessageCount: includedMessages.count,
                excludedMessageCount: excludedMessageCount,
                budget: budget,
                truncationReason: excludedMessageCount > 0 ? .characterBudgetExceeded : nil
            )
        )
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
                for: state.resolvedSelectedModel
            )

        case .empty:
            if let previousSelection = state.selectedModelHandle {
                applyMissingSelectedModel(previousSelection, to: &state)
            }

        case .idle, .loading, .failed:
            if state.selectedModelHandle != nil {
                state.selectedThinking = State.normalizeSelectedThinking(
                state.selectedThinking,
                for: state.resolvedSelectedModel
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

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

let kAiChatHistoryCharacterBudget = 24000

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
              state.pendingRequestStart == nil,
              let sessionID = state.sessionID,
              case let .loaded(models) = state.modelListState,
              let selectedModel = state.resolvedModel(for: state.selectedModelHandle, in: models),
              let preparedRequest = prepareRequest(kind: kind, state: state)
        else { return .none }

        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: UUID(),
            kind: kind,
            sessionID: sessionID,
            selectedModel: selectedModel,
            selectedRow: resolvedSelectedModelRow(in: state),
            preparedRequest: preparedRequest,
        )

        if let requestContextOverride = preparedRequest.requestContextOverride {
            return beginRequest(
                pendingRequest,
                lockedRequestContext: requestContextOverride,
                state: &state,
            )
        }

        let resolverInput = makeRequestContextResolverInput(for: pendingRequest, state: state)
        state.pendingRequestStart = pendingRequest
        return resolveRequestContext(resolutionID: pendingRequest.resolutionID, input: resolverInput)
    }

    func completeRequestContextResolution(
        resolutionID: UUID,
        resolvedContext: AiChatResolvedRequestContext,
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingRequest = state.pendingRequestStart,
              pendingRequest.resolutionID == resolutionID
        else { return .none }

        state.pendingRequestStart = nil
        return beginRequest(
            pendingRequest,
            lockedRequestContext: makeLockedRequestContextSnapshot(from: resolvedContext),
            state: &state,
        )
    }

    private func beginRequest(
        _ pendingRequest: AiChatPendingRequestStart,
        lockedRequestContext: AiChatLockedRequestContextSnapshot,
        state: inout State,
    ) -> Effect<Action> {
        let selectedHandle = pendingRequest.selectedModel.id
        let lock = makeRequestLock(
            input: AiChatRequestLockInput(
                kind: pendingRequest.kind,
                sessionID: pendingRequest.sessionID,
                selectedModel: pendingRequest.selectedModel,
                selectedRow: pendingRequest.selectedRow,
                preparedRequest: pendingRequest.preparedRequest,
            ),
            lockedRequestContext: lockedRequestContext,
            state: state,
        )

        applyRequestStart(
            kind: pendingRequest.kind,
            prompt: pendingRequest.preparedRequest.prompt,
            selectedHandle: selectedHandle,
            lock: lock,
            state: &state,
        )
        let startSnapshotEffect = saveRequestStartSnapshotIfNeeded(kind: pendingRequest.kind, state: state, lock: lock)
        return .merge(startSnapshotEffect, execute(request: lock.request))
    }

    private func resolveRequestContext(
        resolutionID: UUID,
        input: AiChatContextPartResolverInput,
    ) -> Effect<Action> {
        .run { [aiChatContextPartResolverClient] send in
            let resolvedContext = await aiChatContextPartResolverClient.resolve(input)
            await send(.requestContextResolved(resolutionID, resolvedContext))
        }
        .cancellable(id: CancelID.requestContextResolution, cancelInFlight: true)
    }

    private func saveRequestStartSnapshotIfNeeded(
        kind: AiChatRequestKind,
        state: State,
        lock: AiChatRequestLock,
    ) -> Effect<Action> {
        guard kind == .submit else { return .none }
        let snapshot = makeRequestStartSnapshot(state: state, lock: lock)
        return .run { [aiChatSessionPersistenceClient] send in
            do {
                try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.sessionSnapshotUpdated(
                    AiChatSessionSummary(snapshot: snapshot),
                    requestID: lock.requestID,
                    runID: lock.runID,
                ))
            } catch is CancellationError {
                return
            } catch {
                await send(.sessionSnapshotUpdateFailed(requestID: lock.requestID, runID: lock.runID))
            }
        }
        .cancellable(id: CancelID.requestStartPersistence, cancelInFlight: true)
    }

    private func makeRequestStartSnapshot(state: State, lock: AiChatRequestLock) -> AiChatSessionSnapshot {
        guard let sessionID = lock.context.sessionID ?? state.sessionID else {
            preconditionFailure("Missing session ID for request-start snapshot")
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: state.currentSessionCustomTitle,
            provider: lock.context.provider,
            model: lock.context.model,
            selectedModelRow: lock.selectedModelRow,
            selectedThinking: lock.context.selectedThinking,
            transcriptHistory: state.transcriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: persistenceSafeRequestContext(lock.context.requestContext),
            updatedAtMs: lock.context.submittedAtMs ?? currentTimestampMs(),
        )
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

        let selectedHandle = state.resolvedSelectedModelHandle ?? state.selectedModelHandle
        let lastSubmittedContext = lastSubmittedRequestContext(in: state)
        let requestContextOverride = reusableRequestContext(
            from: lastSubmittedContext,
            selectedHandle: selectedHandle,
        )

        return AiChatPreparedRequest(
            prompt: lastUserPrompt,
            messages: truncatedHistory.messages,
            assistantReplacementIndex: assistantReplacementIndex,
            historyTruncation: truncatedHistory.metadata,
            requestContextOverride: requestContextOverride,
            requestContextSource: requestContextOverride == nil ? lastSubmittedContext?.context : nil,
        )
    }

    private func makeRequestLock(
        input: AiChatRequestLockInput,
        lockedRequestContext: AiChatLockedRequestContextSnapshot,
        state: State,
    ) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let submittedAtMs = currentTimestampMs()
        let selectedHandle = input.selectedModel.id
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
            state.emptyDraftSessionID = nil
            if let sessionID = lock.context.sessionID ?? state.sessionID {
                state.sessionList.selectedSessionID = sessionID
                state.sessionList.unreadCompletedSessionIDs.remove(sessionID)
                state.sessionList.replaceRow(processingSessionSummary(prompt: prompt, lock: lock, sessionID: sessionID))
            }
            state.transcriptAutoScrollVersion += 1
        }
    }

    private func processingSessionSummary(
        prompt: String,
        lock: AiChatRequestLock,
        sessionID: AiChatSessionID,
    ) -> AiChatSessionSummary {
        let timestamp = lock.context.submittedAtMs ?? currentTimestampMs()
        return AiChatSessionSummary(
            sessionID: sessionID,
            title: AiChatSessionSummary.automaticTitle(from: prompt),
            preview: prompt,
            messageCount: 1,
            contextTitle: lock.context.currentContext.summary,
            searchText: prompt,
            provider: lock.context.provider,
            model: lock.context.model,
            createdAtMs: timestamp,
            updatedAtMs: timestamp,
            status: .active,
        )
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
           state.transcriptHistory[index].role == .assistant
        {
            state.transcriptHistory[index] = response.assistantMessage
        } else {
            state.transcriptHistory.append(response.assistantMessage)
        }

        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = persistenceSafeRequestContext(lock.context.requestContext)
        state.lastRequestContextModelHandle = lock.context.model
        state.executionPhase = .completed(lock)
        state.transcriptAutoScrollVersion += 1
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
            customTitle: state.currentSessionCustomTitle,
            provider: lock.context.provider,
            model: lock.context.model,
            selectedModelRow: lock.selectedModelRow,
            selectedThinking: lock.context.selectedThinking,
            transcriptHistory: state.transcriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: persistenceSafeRequestContext(lock.context.requestContext),
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

    private func lastSubmittedRequestContext(
        in state: State,
    ) -> (model: AiModelHandle?, context: AiChatLockedRequestContextSnapshot)? {
        if let lock = state.executionPhase.lock {
            return (lock.context.model, lock.context.requestContext)
        }
        guard let context = state.lastRequestContext else { return nil }
        return (state.lastRequestContextModelHandle, context)
    }

    private func reusableRequestContext(
        from submittedContext: (model: AiModelHandle?, context: AiChatLockedRequestContextSnapshot)?,
        selectedHandle: AiModelHandle?,
    ) -> AiChatLockedRequestContextSnapshot? {
        guard let submittedContext else { return nil }
        guard let submittedModel = submittedContext.model else { return submittedContext.context }
        guard submittedModel == selectedHandle else { return nil }
        return submittedContext.context
    }

    func aiChatRequestFamily(for provider: AiProvider) -> AiChatContextPartResolverRequestFamily {
        switch provider {
        case .openai:
            .openAIResponses
        case .anthropic:
            .anthropicMessages
        case .chatgptCodex:
            .codexCLI
        }
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

extension AiChatAttachmentDraft {
    init(snapshot: AiChatAttachmentSnapshot) {
        self.init(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: snapshot.subtitle,
            kind: snapshot.kind,
            sourceLocation: snapshot.sourceLocation,
            metadata: snapshot.metadata,
            currentStatus: .pending,
        )
    }
}

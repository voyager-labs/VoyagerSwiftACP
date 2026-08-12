import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

let kAiChatHistoryCharacterBudget = 24000

struct AiChatRequestLockInput {
    var kind: AiChatRequestKind
    var sessionID: AiChatSessionID
    var selectedModel: AiProviderModel
    var selectedRow: AiModelCatalogRow?
    var selectedThinking: AiThinkingSelection?
    var customTitle: String?
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

        state.invalidatePreparedTransientSession(for: sessionID)
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: UUID(),
            kind: kind,
            sessionID: sessionID,
            selectedModel: selectedModel,
            selectedRow: resolvedSelectedModelRow(in: state),
            selectedThinking: state.selectedThinking,
            customTitle: state.currentSessionCustomTitle,
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
        let lockedRequestContext = makeLockedRequestContextSnapshot(from: resolvedContext)
        if let currentPendingRequest = state.pendingRequestStart,
           currentPendingRequest.resolutionID == resolutionID
        {
            state.pendingRequestStart = nil
            guard AiChatStateSelection.modelCatalogAuthority(
                for: currentPendingRequest.selectedModel.id,
                state: state,
            ) != .confirmedUnavailable else {
                return .none
            }
            return beginRequest(
                currentPendingRequest,
                lockedRequestContext: lockedRequestContext,
                state: &state,
            )
        }

        guard let backgroundPendingRequest = state.backgroundPendingRequestStarts
            .removeValue(forKey: resolutionID)
        else { return .none }
        guard AiChatStateSelection.modelCatalogAuthority(
            for: backgroundPendingRequest.selectedModel.id,
            state: state,
        ) != .confirmedUnavailable else {
            return .none
        }

        if backgroundPendingRequest.sessionID == state.sessionID,
           canBeginForegroundRequest(state: state)
        {
            return beginRequest(
                backgroundPendingRequest,
                lockedRequestContext: lockedRequestContext,
                state: &state,
            )
        }

        return beginBackgroundRequest(
            backgroundPendingRequest,
            lockedRequestContext: lockedRequestContext,
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
                selectedThinking: pendingRequest.selectedThinking,
                customTitle: pendingRequest.customTitle,
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

    private func canBeginForegroundRequest(state: State) -> Bool {
        state.pendingRequestStart == nil && !state.executionPhase.isProcessing
    }

    private func beginBackgroundRequest(
        _ pendingRequest: AiChatPendingRequestStart,
        lockedRequestContext: AiChatLockedRequestContextSnapshot,
        state: inout State,
    ) -> Effect<Action> {
        let lock = makeRequestLock(
            input: AiChatRequestLockInput(
                kind: pendingRequest.kind,
                sessionID: pendingRequest.sessionID,
                selectedModel: pendingRequest.selectedModel,
                selectedRow: pendingRequest.selectedRow,
                selectedThinking: pendingRequest.selectedThinking,
                customTitle: pendingRequest.customTitle,
                preparedRequest: pendingRequest.preparedRequest,
            ),
            lockedRequestContext: lockedRequestContext,
            state: state,
        )
        state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
        let startSnapshotEffect = saveBackgroundRequestStartSnapshotIfNeeded(kind: pendingRequest.kind, lock: lock)
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
        .cancellable(id: CancelID.requestContextResolution(resolutionID), cancelInFlight: true)
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
                let persistedSnapshot = try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.sessionSnapshotUpdated(
                    AiChatSessionSummary(snapshot: persistedSnapshot),
                    snapshot: persistedSnapshot,
                    requestID: lock.requestID,
                    runID: lock.runID,
                ))
            } catch is CancellationError {
                return
            } catch {
                await send(.sessionSnapshotUpdateFailed(requestID: lock.requestID, runID: lock.runID))
            }
        }
        .cancellable(id: CancelID.requestStartPersistence(lock.requestID), cancelInFlight: true)
    }

    private func saveBackgroundRequestStartSnapshotIfNeeded(
        kind: AiChatRequestKind,
        lock: AiChatRequestLock,
    ) -> Effect<Action> {
        guard kind == .submit else { return .none }
        let snapshot = makeBackgroundRequestStartSnapshot(lock: lock)
        return .run { [aiChatSessionPersistenceClient] send in
            do {
                let persistedSnapshot = try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.sessionSnapshotUpdated(
                    AiChatSessionSummary(snapshot: persistedSnapshot),
                    snapshot: persistedSnapshot,
                    requestID: lock.requestID,
                    runID: lock.runID,
                ))
            } catch {
                await send(.sessionSnapshotUpdateFailed(requestID: lock.requestID, runID: lock.runID))
            }
        }
        .cancellable(id: CancelID.requestStartPersistence(lock.requestID), cancelInFlight: true)
    }

    private func makeBackgroundRequestStartSnapshot(lock: AiChatRequestLock) -> AiChatSessionSnapshot {
        guard let sessionID = lock.context.sessionID else {
            preconditionFailure("Missing session ID for background request-start snapshot")
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: lock.customTitle,
            provider: lock.context.provider,
            model: lock.context.model,
            selectedModelRow: lock.selectedModelRow,
            selectedThinking: lock.context.selectedThinking,
            transcriptHistory: lock.persistenceTranscriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: persistenceSafeRequestContext(lock.context.requestContext),
            updatedAtMs: lock.context.submittedAtMs ?? currentTimestampMs(),
        )
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
            persistenceTranscriptHistory: fullMessages,
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
            persistenceTranscriptHistory: messages,
            requestContextOverride: requestContextOverride,
            requestContextSource: requestContextOverride == nil ? lastSubmittedContext?.context : nil,
        )
    }

    private func makeRequestLock(
        input: AiChatRequestLockInput,
        lockedRequestContext: AiChatLockedRequestContextSnapshot,
        state _: State,
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
            selectedThinking: input.selectedThinking,
            sessionStatus: .active,
            currentContext: lockedRequestContext.currentContext,
            requestContext: lockedRequestContext,
            promptSummary: input.preparedRequest.prompt,
            submittedAtMs: submittedAtMs,
        )
        let requestMessages = stampedSubmitMessages(
            input.preparedRequest.messages,
            kind: input.kind,
            submittedAtMs: submittedAtMs,
        )
        let persistenceTranscriptHistory = stampedSubmitMessages(
            input.preparedRequest.persistenceTranscriptHistory,
            kind: input.kind,
            submittedAtMs: submittedAtMs,
        )
        let request = AiChatRequest(context: context, messages: requestMessages)

        return AiChatRequestLock(
            kind: input.kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: input.selectedRow,
            assistantReplacementIndex: input.preparedRequest.assistantReplacementIndex,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
            customTitle: input.customTitle,
            historyTruncation: input.preparedRequest.historyTruncation,
            observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: submittedAtMs),
        )
    }

    func stampedSubmitMessages(
        _ messages: [AiChatMessage],
        kind: AiChatRequestKind,
        submittedAtMs: Int64,
    ) -> [AiChatMessage] {
        guard kind == .submit,
              let userMessage = messages.last,
              userMessage.role == .user
        else { return messages }

        var stampedMessages = messages
        stampedMessages[stampedMessages.index(before: stampedMessages.endIndex)] = AiChatMessage(
            role: userMessage.role,
            content: userMessage.content,
            createdAtMs: submittedAtMs,
        )
        return stampedMessages
    }

    private func applyRequestStart(
        kind: AiChatRequestKind,
        prompt: String,
        selectedHandle: AiModelHandle,
        lock: AiChatRequestLock,
        state: inout State,
    ) {
        let submittedDraftIsUnchanged = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines) == prompt
        preserveFinalPersistenceOwnerBeforeRequestStart(newLock: lock, state: &state)
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamingAssistantDraft = nil
        state.executionPhase = .processing(lock)
        state.sessionStatus = .active

        if kind == .submit {
            if let stampedUserMessage = lock.request.messages.last, stampedUserMessage.role == .user {
                state.transcriptHistory.append(stampedUserMessage)
            }
            if submittedDraftIsUnchanged {
                state.draftText = ""
            }
            state.emptyDraftSessionID = nil
            if let sessionID = lock.context.sessionID ?? state.sessionID {
                state.sessionList.selectedSessionID = sessionID
                state.sessionList.unreadCompletedSessionIDs.remove(sessionID)
                state.sessionList.replaceRow(processingSessionSummary(prompt: prompt, lock: lock, sessionID: sessionID))
            }
            state.transcriptAutoScrollVersion += 1
        }
    }

    private func preserveFinalPersistenceOwnerBeforeRequestStart(
        newLock: AiChatRequestLock,
        state: inout State,
    ) {
        guard let currentLock = state.executionPhase.lock,
              currentLock.requestID != newLock.requestID
        else { return }

        switch state.executionPhase {
        case .completed where currentLock.finalSnapshot != nil,
             .persistenceRecovery:
            state.backgroundExecutionPhases[currentLock.requestID] = state.executionPhase
        case .completed,
             .idle,
             .processing,
             .failed,
             .cancelled:
            break
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
        .cancellable(id: CancelID.request(request.context.requestID), cancelInFlight: false)
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
        lock.requestID == context.requestID
            && lock.runID == context.runID
            && lock.context.sessionID == context.sessionID
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

    func moveVisibleProcessingToBackgroundIfNeeded(state: inout State, targetSessionID: AiChatSessionID?) {
        guard let lock = state.executionPhase.lock,
              lock.context.sessionID != targetSessionID
        else { return }

        switch state.executionPhase {
        case .processing, .completed, .persistenceRecovery:
            state.backgroundExecutionPhases[lock.requestID] = state.executionPhase
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
        case .idle, .failed, .cancelled:
            break
        }
    }

    func cancelRequestLifecycle(for lock: AiChatRequestLock) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.request(lock.requestID)),
            .cancel(id: CancelID.requestStartPersistence(lock.requestID)),
            .cancel(id: CancelID.requestFinalPersistence(lock.requestID)),
            .cancel(id: CancelID.persistenceRecovery(lock.requestID)),
        )
    }

    func cancelRequestLifecycle(for sessionID: AiChatSessionID, state: inout State) -> Effect<Action>? {
        var effects: [Effect<Action>] = []
        if let pendingRequestStart = state.pendingRequestStart,
           pendingRequestStart.sessionID == sessionID
        {
            state.pendingRequestStart = nil
            effects.append(.cancel(id: CancelID.requestContextResolution(pendingRequestStart.resolutionID)))
        }
        let backgroundPendingRequestStarts = state.backgroundPendingRequestStarts.values
            .filter { $0.sessionID == sessionID }
        for pendingRequestStart in backgroundPendingRequestStarts {
            state.backgroundPendingRequestStarts[pendingRequestStart.resolutionID] = nil
            effects.append(.cancel(id: CancelID.requestContextResolution(pendingRequestStart.resolutionID)))
        }
        if let lock = state.executionPhase.lock, lock.context.sessionID == sessionID {
            effects.append(cancelRequestLifecycle(for: lock))
        }

        let backgroundLocks = state.backgroundExecutionPhases.values.compactMap(\.lock)
            .filter { $0.context.sessionID == sessionID }
        for lock in backgroundLocks {
            state.backgroundExecutionPhases[lock.requestID] = nil
            effects.append(cancelRequestLifecycle(for: lock))
        }

        guard !effects.isEmpty else { return nil }
        return .merge(effects)
    }

    func cancelAllRequestLifecycleWork(state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if let pendingRequestStart = state.pendingRequestStart {
            effects.append(.cancel(id: CancelID.requestContextResolution(pendingRequestStart.resolutionID)))
        }
        for pendingRequestStart in state.backgroundPendingRequestStarts.values {
            effects.append(.cancel(id: CancelID.requestContextResolution(pendingRequestStart.resolutionID)))
        }
        if let lock = state.executionPhase.lock {
            effects.append(cancelRequestLifecycle(for: lock))
        }
        for lock in state.backgroundExecutionPhases.values.compactMap(\.lock) {
            effects.append(cancelRequestLifecycle(for: lock))
        }
        state.backgroundPendingRequestStarts = [:]
        state.backgroundExecutionPhases = [:]
        return .merge(effects)
    }

    func cancelAllInFlightWork(state: inout State) -> Effect<Action> {
        .merge(
            cancelAllRequestLifecycleWork(state: &state),
            .cancel(id: CancelID.restore),
            .cancel(id: CancelID.modelList),
            .cancel(id: CancelID.newChat(ownerID: state.cancellationOwnerID)),
            .cancel(id: CancelID.sessionList),
            .cancel(id: CancelID.sessionDelete),
            .cancel(id: CancelID.sessionRename),
            state.sessionID.map { .cancel(id: CancelID.attachmentDrop($0)) } ?? .none,
        )
    }

    func handleCancelTapped(state: inout State) -> Effect<Action> {
        if let pendingRequestStart = state.visiblePendingRequestStart {
            if state.pendingRequestStart?.resolutionID == pendingRequestStart.resolutionID {
                state.pendingRequestStart = nil
            } else {
                state.backgroundPendingRequestStarts[pendingRequestStart.resolutionID] = nil
            }
            return .cancel(id: CancelID.requestContextResolution(pendingRequestStart.resolutionID))
        }
        guard let lock = state.executionPhase.lock, state.executionPhase.isProcessing else { return .none }
        state.lockedModelHandle = nil
        state.streamingAssistantDraft = nil
        state.executionPhase = .cancelled(lock.recordingTerminal(
            at: currentTimestampMs(),
            failure: .cancelled,
            wasCancelled: true,
        ))
        return cancelRequestLifecycle(for: lock)
    }

    func handleResetTapped(state: inout State) -> Effect<Action> {
        let cancellationEffect = cancelAllInFlightWork(state: &state)
        state.pendingRequestStart = nil
        state.invalidatePreparedTransientSession()
        state.emptyDraftSessionID = nil
        state.restoreSessionID = nil
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.draftText = ""
        state.transcriptHistory = []
        state.streamingAssistantDraft = nil
        state.lastExecutionFailure = nil
        state.lockedModelHandle = nil
        state.executionPhase = .idle
        return cancellationEffect
    }

    func handleTeardownRequested(state: inout State) -> Effect<Action> {
        let cancellationEffect = cancelAllInFlightWork(state: &state)
        state.pendingRequestStart = nil
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.executionPhase = .idle
        return cancellationEffect
    }
}

extension AiChatState {
    var visiblePendingRequestStart: AiChatPendingRequestStart? {
        guard let sessionID else { return nil }
        if let pendingRequestStart, pendingRequestStart.sessionID == sessionID {
            return pendingRequestStart
        }
        return backgroundPendingRequestStarts.values.first { $0.sessionID == sessionID }
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

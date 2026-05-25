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
    var requestContextSource: AiChatLockedRequestContextSnapshot? = nil
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

        let selectedHandle = state.resolvedSelectedModelHandle ?? state.selectedModelHandle
        let lastSubmittedContext = lastSubmittedRequestContext(in: state)
        let requestContextOverride = reusableRequestContext(
            from: lastSubmittedContext,
            selectedHandle: selectedHandle
        )

        return AiChatPreparedRequest(
            prompt: lastUserPrompt,
            messages: truncatedHistory.messages,
            assistantReplacementIndex: assistantReplacementIndex,
            historyTruncation: truncatedHistory.metadata,
            requestContextOverride: requestContextOverride,
            requestContextSource: requestContextOverride == nil ? lastSubmittedContext?.context : nil
        )
    }

    private func makeRequestLock(input: AiChatRequestLockInput, state: State) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let submittedAtMs = currentTimestampMs()
        let selectedHandle = input.selectedModel.id
        let lockedRequestContext = input.preparedRequest.requestContextOverride
            ?? input.preparedRequest.requestContextSource.map { makeLockedRequestContextSnapshot(from: $0, state: state) }
            ?? makeLockedRequestContextSnapshot(state: state)
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
        state.lastRequestContext = persistenceSafeRequestContext(lock.context.requestContext)
        state.lastRequestContextModelHandle = lock.context.model
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
        in state: State
    ) -> (model: AiModelHandle?, context: AiChatLockedRequestContextSnapshot)? {
        if let lock = state.executionPhase.lock {
            return (lock.context.model, lock.context.requestContext)
        }
        guard let context = state.lastRequestContext else { return nil }
        return (state.lastRequestContextModelHandle, context)
    }

    private func reusableRequestContext(
        from submittedContext: (model: AiModelHandle?, context: AiChatLockedRequestContextSnapshot)?,
        selectedHandle: AiModelHandle?
    ) -> AiChatLockedRequestContextSnapshot? {
        guard let submittedContext else { return nil }
        guard let submittedModel = submittedContext.model else { return submittedContext.context }
        guard submittedModel == selectedHandle else { return nil }
        return submittedContext.context
    }

    private func makeLockedRequestContextSnapshot(state: State) -> AiChatLockedRequestContextSnapshot {
        let selectedModel = state.resolvedSelectedModel
        let provider = selectedModel?.provider ?? state.selectedModelHandle?.provider ?? .openai
        let rawModelID = selectedModel?.rawModelID ?? state.selectedModelHandle?.rawValue ?? ""
        let requestFamily = aiChatRequestFamily(for: provider)
        let resolvedContext = aiChatContextPartResolverClient.resolve(
            AiChatContextPartResolverInput(
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                currentContext: state.currentContext,
                attachments: state.addedAttachments
            )
        )

        return AiChatLockedRequestContextSnapshot(
            currentContext: resolvedContext.currentContext,
            addedAttachments: resolvedContext.addedAttachments,
            parts: resolvedContext.parts.map { part in
                AiChatLockedContextPartSnapshot(
                    source: part.source == .attachment ? .attachment : .currentContext,
                    resolution: part.resolution,
                    canonicalPath: part.canonicalPath,
                    displayPath: part.displayPath,
                    fileKind: part.fileKind,
                    displayTitle: part.displayTitle,
                    byteCount: part.byteCount,
                    mimeType: part.mimeType
                )
            }
        )
    }

    private func makeLockedRequestContextSnapshot(
        from previousContext: AiChatLockedRequestContextSnapshot,
        state: State
    ) -> AiChatLockedRequestContextSnapshot {
        let selectedModel = state.resolvedSelectedModel
        let provider = selectedModel?.provider ?? state.selectedModelHandle?.provider ?? .openai
        let rawModelID = selectedModel?.rawModelID ?? state.selectedModelHandle?.rawValue ?? ""
        let requestFamily = aiChatRequestFamily(for: provider)
        let resolvedContext = aiChatContextPartResolverClient.resolve(
            AiChatContextPartResolverInput(
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                currentContext: previousContext.currentContext,
                attachments: previousContext.addedAttachments.map(AiChatAttachmentDraft.init(snapshot:))
            )
        )

        return AiChatLockedRequestContextSnapshot(
            currentContext: resolvedContext.currentContext,
            addedAttachments: resolvedContext.addedAttachments,
            parts: resolvedContext.parts.map { part in
                AiChatLockedContextPartSnapshot(
                    source: part.source == .attachment ? .attachment : .currentContext,
                    resolution: part.resolution,
                    canonicalPath: part.canonicalPath,
                    displayPath: part.displayPath,
                    fileKind: part.fileKind,
                    displayTitle: part.displayTitle,
                    byteCount: part.byteCount,
                    mimeType: part.mimeType
                )
            }
        )
    }

    private func persistenceSafeRequestContext(
        _ context: AiChatLockedRequestContextSnapshot
    ) -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: persistenceSafeCurrentContext(context.currentContext),
            addedAttachments: context.addedAttachments.map(persistenceSafeAttachmentSnapshot),
            parts: context.parts.map(persistenceSafeContextPart),
            status: context.status
        )
    }

    private func persistenceSafeCurrentContext(
        _ snapshot: AiChatCurrentContextSnapshot
    ) -> AiChatCurrentContextSnapshot {
        AiChatCurrentContextSnapshot(
            summary: snapshot.summary,
            references: snapshot.references.map(persistenceSafeContextReference),
            items: snapshot.items.map(persistenceSafeContextItem),
            attachments: snapshot.attachments.map(persistenceSafeContextAttachment)
        )
    }

    private func persistenceSafeContextReference(
        _ reference: AiChatContextReference
    ) -> AiChatContextReference {
        AiChatContextReference(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: persistenceSafeMetadata(reference.metadata)
        )
    }

    private func persistenceSafeContextItem(_ item: AiChatContextItem) -> AiChatContextItem {
        AiChatContextItem(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: persistenceSafeMetadata(item.metadata),
            references: item.references.map(persistenceSafeContextReference)
        )
    }

    private func persistenceSafeContextAttachment(
        _ attachment: AiChatContextAttachment
    ) -> AiChatContextAttachment {
        AiChatContextAttachment(
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            kind: attachment.kind,
            metadata: persistenceSafeMetadata(attachment.metadata)
        )
    }

    private func persistenceSafeAttachmentSnapshot(
        _ snapshot: AiChatAttachmentSnapshot
    ) -> AiChatAttachmentSnapshot {
        AiChatAttachmentSnapshot(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: snapshot.subtitle,
            kind: snapshot.kind,
            sourceLocation: snapshot.sourceLocation,
            metadata: persistenceSafeMetadata(snapshot.metadata),
            resolutionResult: persistenceSafeResolutionResult(snapshot.resolutionResult)
        )
    }

    private func persistenceSafeContextPart(
        _ part: AiChatLockedContextPartSnapshot
    ) -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: part.source,
            resolution: persistenceSafeContextPartResolution(part.resolution),
            canonicalPath: part.canonicalPath,
            displayPath: part.displayPath,
            fileKind: part.fileKind,
            displayTitle: part.displayTitle,
            byteCount: part.byteCount,
            mimeType: part.mimeType
        )
    }

    private func persistenceSafeResolutionResult(
        _ resolution: AiChatAttachmentResolutionResult
    ) -> AiChatAttachmentResolutionResult {
        switch resolution {
        case let .resolvedText(text, metadata):
            return .resolvedText(text: text, metadata: persistenceSafeMetadata(metadata))
        case let .resolvedReference(metadata):
            return .resolvedReference(metadata: persistenceSafeMetadata(metadata))
        case let .resolvedPartial(text, truncated, metadata):
            return .resolvedPartial(text: text, truncated: truncated, metadata: persistenceSafeMetadata(metadata))
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: persistenceSafeMetadata(metadata))
        }
    }

    private func persistenceSafeContextPartResolution(
        _ resolution: AiChatContextPartResolution
    ) -> AiChatContextPartResolution {
        switch resolution {
        case let .inlineText(text, metadata):
            return .inlineText(text: text, metadata: persistenceSafeMetadata(metadata))
        case let .partialText(text, truncated, metadata):
            return .partialText(text: text, truncated: truncated, metadata: persistenceSafeMetadata(metadata))
        case let .referenceOnly(metadata):
            return .referenceOnly(metadata: persistenceSafeMetadata(metadata))
        case let .collectionPathList(paths, metadata):
            return .collectionPathList(paths: paths, metadata: persistenceSafeMetadata(metadata))
        case let .providerNativeFile(kind, mimeType, metadata):
            return .providerNativeFile(kind: kind, mimeType: mimeType, metadata: persistenceSafeMetadata(metadata))
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: persistenceSafeMetadata(metadata))
        }
    }

    private func persistenceSafeMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.filter { key, _ in
            !["base64Data", "nativeBase64Data", "fileDataBase64"].contains(key)
        }
    }

    private func aiChatRequestFamily(for provider: AiProvider) -> AiChatContextPartResolverRequestFamily {
        switch provider {
        case .openai:
            return .openAIResponses
        case .anthropic:
            return .anthropicMessages
        case .chatgptCodex:
            return .codexCLI
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


private extension AiChatAttachmentDraft {
    init(snapshot: AiChatAttachmentSnapshot) {
        self.init(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: snapshot.subtitle,
            kind: snapshot.kind,
            sourceLocation: snapshot.sourceLocation,
            metadata: snapshot.metadata,
            currentStatus: .pending
        )
    }
}

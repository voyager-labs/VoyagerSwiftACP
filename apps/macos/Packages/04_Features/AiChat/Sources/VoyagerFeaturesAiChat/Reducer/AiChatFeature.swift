import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiChatFeature {
    public typealias State = AiChatState
    public typealias Action = AiChatAction

    enum CancelID: Hashable, Sendable {
        case request
        case requestStartPersistence
        case requestFinalPersistence
        case restore
        case persistenceRecovery
        case modelList
        case sessionList
        case sessionDelete
        case sessionRename
        case newChat
    }

    @Dependency(\.aiChatExecutionClient)
    var aiChatExecutionClient
    @Dependency(\.aiChatSessionPersistenceClient)
    var aiChatSessionPersistenceClient
    @Dependency(\.aiChatAttachmentResolverClient)
    var aiChatAttachmentResolverClient
    @Dependency(\.aiChatContextPartResolverClient)
    var aiChatContextPartResolverClient
    @Dependency(\.aiProviderModelListClient)
    var aiProviderModelListClient
    @Dependency(\.aiConnectionsFileClient)
    var aiConnectionsFileClient
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.date)
    var date

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                normalizeSelectionIfNeeded(&state)
                return .none

            case .sessionsAppeared:
                state.mode = .sessions
                state.sessionList.isLoading = true
                state.sessionList.errorMessage = nil
                return loadSessions()

            case .newChatTapped:
                let snapshot = startNewUnselectedChat(state: &state)
                return .concatenate(
                    cancelRequestLifecycle(),
                    saveNewChat(snapshot)
                )

            case .startNewChatFromRebindTapped:
                let snapshot = startNewUnselectedChat(state: &state)
                return .concatenate(
                    cancelRequestLifecycle(),
                    saveNewChat(snapshot)
                )

            case .rebindContextTapped:
                state.sessionStatus = .active
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.unavailableSelectedModelHandle = nil
                normalizeSelectionIfNeeded(&state)
                return .none

            case let .sessionRowTapped(sessionID):
                state.emptyDraftSessionID = nil
                state.sessionList.cancelRenaming()
                state.sessionList.selectedSessionID = sessionID
                state.sessionList.unreadCompletedSessionIDs.remove(sessionID)
                state.sessionList.errorMessage = nil

                if state.executionPhase.isProcessing, state.sessionID == sessionID {
                    state.mode = .chat
                    return .none
                }

                state.mode = .sessions
                state.restoreSessionID = sessionID
                let shouldCancelPreviousRequestLifecycle = state.sessionID != nil && state.sessionID != sessionID
                if case let .processing(lock) = state.executionPhase,
                   state.sessionID != sessionID
                {
                    state.lockedModelHandle = nil
                    state.streamingAssistantDraft = nil
                    state.executionPhase = .cancelled(lock.recordingTerminal(
                        at: currentTimestampMs(),
                        failure: .cancelled,
                        wasCancelled: true
                    ))
                }

                let restoreEffect = restoreSession(sessionID: sessionID, state: state)
                guard shouldCancelPreviousRequestLifecycle else {
                    return restoreEffect
                }
                return .concatenate(
                    cancelRequestLifecycle(),
                    restoreEffect
                )

            case let .deleteSessionTapped(sessionID):
                state.sessionList.errorMessage = nil
                if state.sessionList.renamingSessionID == sessionID {
                    state.sessionList.cancelRenaming()
                }

                var preDeleteEffects: [Effect<Action>] = []
                if state.restoreSessionID == sessionID {
                    state.restoreSessionID = nil
                    state.restoreOutcome = nil
                    state.restoreFailure = nil
                    state.sessionList.selectedSessionID = nil
                    preDeleteEffects.append(.cancel(id: CancelID.restore))
                }
                if state.sessionID == sessionID {
                    if case let .processing(lock) = state.executionPhase {
                        state.lockedModelHandle = nil
                        state.streamingAssistantDraft = nil
                        state.executionPhase = .cancelled(lock.recordingTerminal(
                            at: currentTimestampMs(),
                            failure: .cancelled,
                            wasCancelled: true
                        ))
                    }
                    preDeleteEffects.append(cancelRequestLifecycle())
                }
                guard !preDeleteEffects.isEmpty else {
                    return deleteSession(sessionID)
                }
                return .concatenate(
                    .merge(preDeleteEffects),
                    deleteSession(sessionID)
                )

            case let .renameSessionTapped(sessionID):
                state.sessionList.errorMessage = nil
                state.sessionList.beginRenaming(sessionID: sessionID)
                return .none

            case let .renameSessionTitleChanged(title):
                state.sessionList.renameDraftText = title
                return .none

            case .renameSessionCancelled:
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                return .none

            case .renameSessionConfirmed:
                guard let sessionID = state.sessionList.renamingSessionID else { return .none }
                let title = state.sessionList.renameDraftText
                state.sessionList.errorMessage = nil
                return renameSession(sessionID: sessionID, title: title)

            case let .sessionRenameSucceeded(summary, customTitle):
                state.sessionList.replaceRow(summary)
                if state.sessionID == summary.sessionID {
                    state.currentSessionCustomTitle = customTitle
                }
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                return .none

            case let .sessionRenameFailed(_, message):
                state.sessionList.errorMessage = message
                return .none

            case let .sessionSnapshotUpdated(summary, requestID, runID):
                guard case let .processing(lock) = state.executionPhase,
                      lock.requestID == requestID,
                      lock.runID == runID,
                      !state.sessionList.deletedSessionIDs.contains(summary.sessionID)
                else { return .none }
                state.sessionList.replaceRow(summary)
                state.sessionList.selectedSessionID = summary.sessionID
                state.sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
                state.sessionList.errorMessage = nil
                return .none

            case let .sessionSnapshotUpdateFailed(requestID, runID):
                guard case let .processing(lock) = state.executionPhase,
                      lock.requestID == requestID,
                      lock.runID == runID
                else { return .none }
                return .none

            case let .sessionSnapshotSaved(summary):
                guard !state.sessionList.deletedSessionIDs.contains(summary.sessionID) else {
                    return .none
                }
                state.sessionList.replaceRow(summary)
                if state.restoreSessionID == nil || state.restoreSessionID == summary.sessionID {
                    state.sessionList.selectedSessionID = summary.sessionID
                }
                if state.mode == .chat, state.sessionID == summary.sessionID {
                    state.sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
                } else {
                    state.sessionList.unreadCompletedSessionIDs.insert(summary.sessionID)
                }
                state.sessionList.errorMessage = nil
                return .none

            case .backToSessionsTapped:
                state.mode = .sessions
                guard let emptyDraftSessionID = cleanupEligibleEmptyDraftSessionID(for: state) else {
                    return .none
                }
                state.emptyDraftSessionID = nil
                state.sessionID = nil
                state.restoreSessionID = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.sessionList.selectedSessionID = nil
                state.sessionList.errorMessage = nil
                return deleteSession(emptyDraftSessionID)

            case let .sessionSearchQueryChanged(query):
                state.sessionList.updateQuery(query)
                return .none

            case let .sessionListLoaded(rows):
                state.sessionList.setLoadedRows(rows)
                state.sessionList.isLoading = false
                state.sessionList.errorMessage = nil
                return .none

            case let .sessionListFailed(message):
                state.sessionList.setLoadedRows([])
                state.sessionList.isLoading = false
                state.sessionList.errorMessage = message
                return .none

            case let .sessionDeleteSucceeded(sessionID):
                state.sessionList.removeRow(sessionID: sessionID)
                if state.restoreSessionID == sessionID {
                    state.restoreSessionID = nil
                    state.restoreOutcome = nil
                    state.restoreFailure = nil
                }
                return .none

            case let .sessionDeleteFailed(_, message):
                state.sessionList.errorMessage = message
                return .none

            case let .newChatCreated(snapshot):
                applyNewSessionSnapshot(snapshot, state: &state)
                state.emptyDraftSessionID = snapshot.sessionID
                state.restoreSessionID = snapshot.sessionID
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.mode = .chat
                state.sessionList.selectedSessionID = snapshot.sessionID
                state.sessionList.errorMessage = nil
                return .none

            case let .newChatFailed(message):
                state.emptyDraftSessionID = nil
                state.currentSessionCustomTitle = nil
                state.mode = .sessions
                state.sessionList.selectedSessionID = nil
                state.sessionList.errorMessage = message
                return .none

            case let .setup(setup):
                state.emptyDraftSessionID = nil
                state.currentSessionCustomTitle = nil
                apply(setup: setup, to: &state)
                normalizeSelectionIfNeeded(&state)
                guard let restoreSessionID = state.restoreSessionID else { return .none }
                state.sessionStatus = .restoring
                return restoreSession(sessionID: restoreSessionID, state: state)

            case let .providerConnectionsUpdated(file):
                guard let loadBatch = makeModelListLoadBatch(from: file, state: state) else {
                    state.providerConnectionSnapshot = .known([])
                    state.availableModelsByProvider = [:]
                    clearModelListTracking(&state)
                    state.modelListProvider = nil
                    applyModelListState(.empty, to: &state)
                    return .cancel(id: CancelID.modelList)
                }

                let connectedProviders = loadBatch.requests.map(\.provider)
                state.providerConnectionSnapshot = .known(connectedProviders)
                state.availableModelsByProvider = [:]
                state.modelListRequestID = loadBatch.requestID
                state.modelListProvider = loadBatch.requests.first?.provider
                state.modelListProviderOrder = connectedProviders
                state.modelListPendingProviders = Set(connectedProviders)
                state.modelListLoadedModelsByProvider = [:]
                state.modelListFailedProviders = [:]
                applyModelListState(.loading, to: &state)

                return .concatenate(
                    .cancel(id: CancelID.modelList),
                    .merge(loadBatch.requests.map { loadRequest in
                        .send(.modelListLoading(
                            requestID: loadRequest.requestID,
                            provider: loadRequest.provider,
                            credential: loadRequest.credential
                        ))
                    })
                )

            case let .modelListLoading(requestID, provider, credential):
                guard state.modelListRequestID == requestID,
                      state.modelListPendingProviders.contains(provider)
                else { return .none }
                state.modelListProvider = provider
                return loadModelList(requestID: requestID, provider: provider, credential: credential)

            case let .modelListLoaded(requestID, provider, models):
                guard state.modelListRequestID == requestID,
                      state.modelListPendingProviders.contains(provider)
                else { return .none }

                state.modelListProvider = provider
                state.modelListPendingProviders.remove(provider)
                state.modelListLoadedModelsByProvider[provider] = models
                state.modelListFailedProviders[provider] = nil
                finalizeModelListBatchIfNeeded(&state)
                return .none

            case let .modelListLoadFailed(requestID, provider, failure):
                guard state.modelListRequestID == requestID,
                      state.modelListPendingProviders.contains(provider)
                else { return .none }

                state.modelListProvider = provider
                state.modelListPendingProviders.remove(provider)
                state.modelListLoadedModelsByProvider[provider] = nil
                state.modelListFailedProviders[provider] = failure
                finalizeModelListBatchIfNeeded(&state)
                return .none

            case .modelSelectorTapped:
                state.isModelSelectorPresented = true
                return .none

            case .modelSelectorDismissed:
                state.isModelSelectorPresented = false
                return .none

            case let .selectedModelChanged(handle):
                let resolvedHandle = state.normalizedSelectionHandle(handle)
                guard state.selectedModelHandle != resolvedHandle else { return .none }
                state.selectedModelHandle = resolvedHandle
                state.unavailableSelectedModelHandle = nil
                normalizeSelectionIfNeeded(&state)
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case let .selectedThinkingChanged(selectedThinking):
                guard state.selectedThinking != selectedThinking else { return .none }
                state.selectedThinking = selectedThinking
                normalizeSelectionIfNeeded(&state)
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case let .currentContextChanged(snapshot):
                state.currentContext = currentContextSnapshot(snapshot, excluding: state.addedAttachments)
                return .none

            case let .draftTextChanged(text):
                state.draftText = text
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case .attachmentPickerTapped:
                return .send(.delegate(.requestAttachmentPicker))

            case let .attachmentPickerSelection(urls):
                _ = addAttachmentDrafts(from: urls, skippingCurrentContextDuplicates: true, state: &state)
                return .none

            case let .attachmentDropSelection(urls):
                let didAddAttachments = addAttachmentDrafts(
                    from: urls,
                    skippingCurrentContextDuplicates: false,
                    state: &state
                )
                guard didAddAttachments else { return .none }
                removeCurrentContextDuplicates(state: &state)
                return .send(.delegate(.clearCurrentContextSelection))

            case let .removeAddedAttachment(id):
                removeAddedAttachment(id, state: &state)
                return .none

            case .openSettingsTapped:
                return .send(.delegate(.openAISettings))

            case .delegate:
                return .none

            case .errorRecoveryTapped:
                return recoverFromError(state: &state)

            case .submitTapped:
                guard state.canSubmit else { return .none }
                state.emptyDraftSessionID = nil
                return startRequest(kind: .submit, state: &state)

            case .regenerateTapped:
                return startRequest(kind: .regenerate, state: &state)

            case .cancelTapped:
                guard let lock = state.executionPhase.lock, state.executionPhase.isProcessing else { return .none }
                state.lockedModelHandle = nil
                state.streamingAssistantDraft = nil
                state.executionPhase = .cancelled(lock.recordingTerminal(
                    at: currentTimestampMs(),
                    failure: .cancelled,
                    wasCancelled: true
                ))
                return cancelRequestLifecycle()

            case .resetTapped:
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
                return cancelAllInFlightWork()

            case .teardownRequested:
                state.streamingAssistantDraft = nil
                state.lockedModelHandle = nil
                state.executionPhase = .idle
                return cancelAllInFlightWork()

            case let .restoreOutcome(requestedSessionID, result, restoreFailure):
                guard state.restoreSessionID == requestedSessionID else { return .none }
                let isSessionListRestore = state.mode == .sessions && state.sessionList.selectedSessionID == requestedSessionID
                if isSessionListRestore,
                   let restoreFailure,
                   restoreFailure != .contextMismatch
                {
                    state.sessionList.selectedSessionID = nil
                    state.sessionList.errorMessage = sessionRestoreFailureMessage(for: restoreFailure)
                    return .none
                }
                applyRestoreOutcome(result, restoreFailure: restoreFailure, state: &state)
                if isSessionListRestore {
                    state.mode = .chat
                    state.sessionList.errorMessage = nil
                }
                return .none

            case let .executionEvent(event):
                return handleExecutionEvent(event, state: &state)

            case let .persistenceFailed(lock, failure):
                switch state.executionPhase {
                case let .completed(currentLock):
                    guard currentLock.requestID == lock.requestID else { return .none }
                case let .persistenceRecovery(currentLock, _):
                    guard currentLock.requestID == lock.requestID else { return .none }
                default:
                    return .none
                }

                state.executionPhase = .persistenceRecovery(lock, failure)
                state.lastExecutionFailure = failure
                return .none

            case let .persistenceRecoverySucceeded(lock):
                guard case let .persistenceRecovery(currentLock, _) = state.executionPhase,
                      currentLock.requestID == lock.requestID
                else { return .none }
                state.executionPhase = .completed(lock)
                state.lastExecutionFailure = nil
                return .none

            case let .persistenceRecoveryRetryFailed(lock, failure):
                guard case let .persistenceRecovery(currentLock, _) = state.executionPhase,
                      currentLock.requestID == lock.requestID
                else { return .none }
                state.executionPhase = .persistenceRecovery(lock, failure)
                state.lastExecutionFailure = failure
                return .none
            }
        }
    }


    private func cancelRequestLifecycle() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.request),
            .cancel(id: CancelID.requestStartPersistence),
            .cancel(id: CancelID.requestFinalPersistence)
        )
    }

    private func cancelAllInFlightWork() -> Effect<Action> {
        .merge(
            cancelRequestLifecycle(),
            .cancel(id: CancelID.restore),
            .cancel(id: CancelID.persistenceRecovery),
            .cancel(id: CancelID.modelList),
            .cancel(id: CancelID.newChat),
            .cancel(id: CancelID.sessionList),
            .cancel(id: CancelID.sessionDelete),
            .cancel(id: CancelID.sessionRename)
        )
    }
}

private struct AiChatModelListLoadRequest: Equatable, Sendable {
    var requestID: UUID
    var provider: AiProvider
    var credential: StoredCredentialPayload?
}

private struct AiChatModelListLoadBatch: Equatable, Sendable {
    var requestID: UUID
    var requests: [AiChatModelListLoadRequest]
}

private extension AiChatFeature {
    func makeModelListLoadBatch(from file: AIConnectionsFile, state: State) -> AiChatModelListLoadBatch? {
        let preferredProviders = [
            state.selectedModelHandle?.provider,
            state.unavailableSelectedModelHandle?.provider,
            state.lockedModelHandle?.provider,
            state.modelListProvider,
            file.lastUsedProviderId,
        ].compactMap(\.self)

        let connectedRecords = file.providers.values.filter { $0.snapshot.lastKnownStatus == .connected }
        guard !connectedRecords.isEmpty else { return nil }

        let connectedRecordsByProvider = Dictionary(uniqueKeysWithValues: connectedRecords.map { ($0.providerId, $0) })
        var orderedProviders: [AiProvider] = []

        for provider in preferredProviders
            where connectedRecordsByProvider[provider] != nil && !orderedProviders.contains(provider)
        {
            orderedProviders.append(provider)
        }

        for provider in connectedRecordsByProvider.keys.sorted(by: { $0.rawValue < $1.rawValue })
            where !orderedProviders.contains(provider)
        {
            orderedProviders.append(provider)
        }

        guard !orderedProviders.isEmpty else { return nil }

        let requestID = uuid()
        return AiChatModelListLoadBatch(
            requestID: requestID,
            requests: orderedProviders.compactMap { provider in
                guard let record = connectedRecordsByProvider[provider] else { return nil }
                return AiChatModelListLoadRequest(
                    requestID: requestID,
                    provider: provider,
                    credential: record.credential
                )
            }
        )
    }

    func loadModelList(
        requestID: UUID,
        provider: AiProvider,
        credential: StoredCredentialPayload?
    ) -> Effect<Action> {
        .run { [aiProviderModelListClient] send in
            do {
                let models = try await aiProviderModelListClient.loadModels(provider, credential)
                await send(.modelListLoaded(requestID: requestID, provider: provider, models: models))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.modelListLoadFailed(
                    requestID: requestID,
                    provider: provider,
                    failure: Self.makeModelListFailure(provider: provider, error: error)
                ))
            }
        }
        .cancellable(id: CancelID.modelList)
    }

    func applyModelListState(_ modelListState: AiChatModelListState, to state: inout State) {
        state.modelListState = modelListState

        switch modelListState {
        case let .loaded(models):
            state.catalogRows = State.makeCatalogRows(for: models, preserving: state.catalogRows)
            if let currentSelection = state.selectedModelHandle,
               let resolvedSelection = state.normalizedSelectionHandle(currentSelection, in: models)
            {
                state.selectedModelHandle = resolvedSelection
                state.unavailableSelectedModelHandle = nil
            } else if let currentSelection = state.selectedModelHandle {
                applyMissingSelectedModel(currentSelection, to: &state)
            }

        case .empty:
            if let previousSelection = state.selectedModelHandle {
                applyMissingSelectedModel(previousSelection, to: &state)
            }
            state.catalogRows = []

        case .idle, .loading, .failed:
            if case .idle = modelListState {
                state.availableModelsByProvider = [:]
            }
            if case .failed = modelListState {
                state.availableModelsByProvider = [:]
            }
        }

        normalizeSelectionIfNeeded(&state)
        clearRetryBlockingFailureIfNeeded(&state)
    }

    func finalizeModelListBatchIfNeeded(_ state: inout State) {
        guard state.modelListPendingProviders.isEmpty else { return }

        let loadedModelsByProvider = state.modelListProviderOrder
            .reduce(into: [AiProvider: [AiProviderModel]]()) { partialResult, provider in
                partialResult[provider] = state.modelListLoadedModelsByProvider[provider] ?? []
            }
        let mergedModels = state.modelListProviderOrder.flatMap { provider in
            loadedModelsByProvider[provider] ?? []
        }
        let firstFailure = state.modelListProviderOrder
            .first { provider in
                state.modelListFailedProviders[provider] != nil
            }
            .flatMap { provider in
                state.modelListFailedProviders[provider]
            }

        let nextModelListState: AiChatModelListState = if !mergedModels.isEmpty {
            .loaded(mergedModels)
        } else if let failure = firstFailure {
            .failed(failure)
        } else {
            .empty
        }

        state.availableModelsByProvider = loadedModelsByProvider
        state.modelListRequestID = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        applyModelListState(nextModelListState, to: &state)
    }

    func clearModelListTracking(_ state: inout State) {
        state.modelListRequestID = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
    }

    static func makeModelListFailure(provider: AiProvider, error: Error) -> AiModelListFailure {
        let providerDisplayName = ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue

        if let error = error as? AiProviderModelListError {
            let message = switch error {
            case .missingCredential:
                "\(providerDisplayName) credential is missing."
            case .invalidCredential:
                "\(providerDisplayName) credential is invalid."
            case .unsupportedProvider:
                "\(providerDisplayName) model listing is unavailable."
            case .invalidResponse:
                "\(providerDisplayName) returned an invalid model list response."
            case let .httpError(_, statusCode, _):
                "\(providerDisplayName) model list request failed (\(statusCode))."
            case .networkError:
                "\(providerDisplayName) model list request failed due to a network error."
            }
            let reason: AiModelListFailureReason = if case .unsupportedProvider = error {
                .unsupportedProvider
            } else {
                .generic
            }
            return AiModelListFailure(message: message, reason: reason)
        }

        return AiModelListFailure(message: "Unable to load models for \(providerDisplayName).")
    }
}

private extension AiChatFeature {
    func removeCurrentContextDuplicates(state: inout State) {
        state.currentContext = currentContextSnapshot(state.currentContext, excluding: state.addedAttachments)
    }

    func currentContextSnapshot(
        _ snapshot: AiChatCurrentContextSnapshot,
        excluding attachments: [AiChatAttachmentDraft]
    ) -> AiChatCurrentContextSnapshot {
        let attachmentPaths = Set(attachments.compactMap(normalizedAttachmentPath(for:)))
        guard !attachmentPaths.isEmpty else { return snapshot }

        let references = snapshot.references.filter { reference in
            !currentContextPaths(for: reference).contains(where: { attachmentPaths.contains($0) })
        }
        let items = snapshot.items.compactMap { item -> AiChatContextItem? in
            guard !currentContextPaths(for: item).contains(where: { attachmentPaths.contains($0) }) else {
                return nil
            }
            let itemReferences = item.references.filter { reference in
                !currentContextPaths(for: reference).contains(where: { attachmentPaths.contains($0) })
            }
            return AiChatContextItem(
                kind: item.kind,
                identifier: item.identifier,
                title: item.title,
                subtitle: item.subtitle,
                metadata: item.metadata,
                references: itemReferences
            )
        }
        let contextAttachments = snapshot.attachments.filter { attachment in
            !currentContextPaths(for: attachment).contains(where: { attachmentPaths.contains($0) })
        }

        guard references.count != snapshot.references.count
            || items.count != snapshot.items.count
            || contextAttachments.count != snapshot.attachments.count
        else { return snapshot }

        let summary = currentContextSummary(
            references: references,
            items: items,
            attachments: contextAttachments
        )
        return AiChatCurrentContextSnapshot(
            summary: summary,
            references: references,
            items: items,
            attachments: contextAttachments
        )
    }

    func currentContextSummary(
        references: [AiChatContextReference],
        items: [AiChatContextItem],
        attachments: [AiChatContextAttachment]
    ) -> String? {
        if items.count == 1 {
            return items[0].title ?? currentContextDisplayName(from: items[0].identifier)
        }
        if items.count > 1 {
            return "\(items.count) selected"
        }
        if let reference = references.first {
            return reference.title ?? currentContextDisplayName(from: reference.identifier)
        }
        if let attachment = attachments.first {
            return attachment.title ?? currentContextDisplayName(from: attachment.identifier)
        }
        return nil
    }

    func currentContextPaths(for reference: AiChatContextReference) -> [String] {
        normalizedCurrentContextPaths(
            metadata: reference.metadata,
            identifier: reference.identifier,
            subtitle: reference.subtitle
        )
    }

    func currentContextPaths(for item: AiChatContextItem) -> [String] {
        normalizedCurrentContextPaths(
            metadata: item.metadata,
            identifier: item.identifier,
            subtitle: item.subtitle
        )
    }

    func currentContextPaths(for attachment: AiChatContextAttachment) -> [String] {
        normalizedCurrentContextPaths(
            metadata: attachment.metadata,
            identifier: attachment.identifier,
            subtitle: attachment.subtitle
        )
    }

    func normalizedCurrentContextPaths(
        metadata: [String: String],
        identifier: String,
        subtitle: String?
    ) -> [String] {
        var paths: [String] = []
        for value in [metadata["path"], metadata["filePath"], subtitle, identifier].compactMap(\.self) {
            guard let path = normalizedCurrentContextPath(from: value), !paths.contains(path) else { continue }
            paths.append(path)
        }
        return paths
    }

    func normalizedCurrentContextPath(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return normalizedFileURL(from: URL(fileURLWithPath: trimmed))?.path(percentEncoded: false)
    }

    func currentContextDisplayName(from value: String) -> String {
        guard let path = normalizedCurrentContextPath(from: value) else { return value }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }

    @discardableResult
    func addAttachmentDrafts(
        from urls: [URL],
        skippingCurrentContextDuplicates: Bool,
        state: inout State
    ) -> Bool {
        var didAddAttachments = false
        var knownPaths = Set(state.addedAttachments.compactMap(normalizedAttachmentPath(for:)))
        let currentContextPaths = skippingCurrentContextDuplicates
            ? Set(currentContextPaths(for: state.currentContext))
            : []

        for url in urls {
            guard let draft = makeAttachmentDraft(from: url) else { continue }
            let normalizedPath = normalizedAttachmentPath(for: draft) ?? draft.id.rawValue
            guard !currentContextPaths.contains(normalizedPath) else { continue }
            guard knownPaths.insert(normalizedPath).inserted else { continue }
            state.addedAttachments.append(draft)
            didAddAttachments = true
        }
        return didAddAttachments
    }

    func currentContextPaths(for snapshot: AiChatCurrentContextSnapshot) -> [String] {
        var paths: [String] = []
        for reference in snapshot.references {
            appendUnique(currentContextPaths(for: reference), to: &paths)
        }
        for item in snapshot.items {
            appendUnique(currentContextPaths(for: item), to: &paths)
            for reference in item.references {
                appendUnique(currentContextPaths(for: reference), to: &paths)
            }
        }
        for attachment in snapshot.attachments {
            appendUnique(currentContextPaths(for: attachment), to: &paths)
        }
        return paths
    }

    func appendUnique(_ newPaths: [String], to paths: inout [String]) {
        for path in newPaths where !paths.contains(path) {
            paths.append(path)
        }
    }

    func removeAddedAttachment(_ id: AiChatAttachmentID, state: inout State) {
        state.addedAttachments.removeAll { $0.id == id }
    }

    func makeAttachmentDraft(from url: URL) -> AiChatAttachmentDraft? {
        guard let normalizedURL = normalizedFileURL(from: url) else { return nil }
        let normalizedPath = normalizedURL.path(percentEncoded: false)
        guard !normalizedPath.isEmpty else { return nil }

        return AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: normalizedPath),
            source: attachmentSource(for: normalizedURL),
            displayTitle: normalizedURL.lastPathComponent.isEmpty ? nil : normalizedURL.lastPathComponent,
            sourceLocation: AiChatAttachmentSourceLocation(fileURL: normalizedURL, filePath: normalizedPath)
        )
    }

    func normalizedAttachmentPath(for draft: AiChatAttachmentDraft) -> String? {
        if let fileURL = draft.sourceLocation.fileURL, let normalizedURL = normalizedFileURL(from: fileURL) {
            let path = normalizedURL.path(percentEncoded: false)
            if !path.isEmpty { return path }
        }
        if let filePath = draft.sourceLocation.filePath,
           let normalizedURL = normalizedFileURL(from: URL(fileURLWithPath: filePath))
        {
            let path = normalizedURL.path(percentEncoded: false)
            if !path.isEmpty { return path }
        }
        return nil
    }

    func normalizedFileURL(from url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return url.standardizedFileURL
    }


    func cleanupEligibleEmptyDraftSessionID(for state: State) -> AiChatSessionID? {
        guard let emptyDraftSessionID = state.emptyDraftSessionID,
              let sessionID = state.sessionID,
              emptyDraftSessionID == sessionID,
              state.sessionStatus == .idle,
              state.transcriptHistory.isEmpty,
              state.streamingAssistantDraft == nil,
              state.lastRequestContext == nil
        else { return nil }

        return emptyDraftSessionID
    }

    func loadSessions() -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                let rows = try await aiChatSessionPersistenceClient.listSessions(nil, nil)
                await send(.sessionListLoaded(rows))
            } catch is CancellationError {
                return
            } catch {
                await send(.sessionListFailed(Self.sessionListFailureMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.sessionList, cancelInFlight: true)
    }

    func startNewUnselectedChat(state: inout State) -> AiChatSessionSnapshot {
        let sessionID = AiChatSessionID(rawValue: uuid())
        state.sessionID = sessionID
        state.emptyDraftSessionID = sessionID
        state.sessionStatus = .idle
        state.mode = .chat
        state.restoreSessionID = nil
        state.currentSessionCustomTitle = nil
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionList.selectedSessionID = nil
        state.sessionList.errorMessage = nil
        state.transcriptHistory = []
        state.draftText = ""
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = nil
        state.lastRequestContextModelHandle = nil
        state.executionPhase = .idle
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.unavailableSelectedModelHandle = nil

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .idle,
            customTitle: nil,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: currentTimestampMs()
        )
    }

    func saveNewChat(_ snapshot: AiChatSessionSnapshot) -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.newChatCreated(snapshot))
            } catch is CancellationError {
                return
            } catch {
                await send(.newChatFailed(Self.newChatFailureMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.newChat, cancelInFlight: true)
    }


    func renameSession(sessionID: AiChatSessionID, title: String) -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                guard let snapshot = try await aiChatSessionPersistenceClient.loadSession(sessionID) else {
                    await send(.sessionRenameFailed(sessionID, Self.sessionRenameFailureMessage(for: nil)))
                    return
                }
                let renamedSnapshot = Self.snapshot(snapshot, renamedTo: title, updatedAtMs: snapshot.updatedAtMs)
                try await aiChatSessionPersistenceClient.saveSession(renamedSnapshot)
                await send(.sessionRenameSucceeded(
                    AiChatSessionSummary(snapshot: renamedSnapshot),
                    customTitle: renamedSnapshot.customTitle
                ))
            } catch is CancellationError {
                return
            } catch {
                await send(.sessionRenameFailed(sessionID, Self.sessionRenameFailureMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.sessionRename, cancelInFlight: true)
    }

    static func snapshot(
        _ snapshot: AiChatSessionSnapshot,
        renamedTo title: String,
        updatedAtMs: Int64
    ) -> AiChatSessionSnapshot {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForSessionRename
        return AiChatSessionSnapshot(
            sessionID: snapshot.sessionID,
            status: snapshot.status,
            customTitle: normalizedTitle,
            provider: snapshot.provider,
            model: snapshot.model,
            selectedModelRow: snapshot.selectedModelRow,
            selectedThinking: snapshot.selectedThinking,
            transcriptHistory: snapshot.transcriptHistory,
            lastRequestID: snapshot.lastRequestID,
            lastRunID: snapshot.lastRunID,
            lastRequestContext: snapshot.lastRequestContext,
            updatedAtMs: updatedAtMs
        )
    }

    func deleteSession(_ sessionID: AiChatSessionID) -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                try await aiChatSessionPersistenceClient.deleteSession(sessionID)
                await send(.sessionDeleteSucceeded(sessionID))
            } catch is CancellationError {
                return
            } catch {
                await send(.sessionDeleteFailed(sessionID, Self.sessionDeleteFailureMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.sessionDelete, cancelInFlight: false)
    }

    static func sessionListFailureMessage(for error: Error) -> String {
        guard let persistenceError = error as? AiChatSessionPersistenceClientError else {
            return "Chat history could not be loaded."
        }

        switch persistenceError {
        case .applicationSupportDirectoryUnavailable:
            return "Chat history is unavailable right now."
        case .corruptedRecord:
            return "A saved chat could not be read."
        }
    }

    static func newChatFailureMessage(for error: Error) -> String {
        guard let persistenceError = error as? AiChatSessionPersistenceClientError else {
            return "A new chat could not be saved."
        }

        switch persistenceError {
        case .applicationSupportDirectoryUnavailable:
            return "A new chat could not be saved right now."
        case .corruptedRecord:
            return "A new chat could not be saved because chat history is corrupted."
        }
    }

    static func sessionRenameFailureMessage(for error: Error?) -> String {
        guard let persistenceError = error as? AiChatSessionPersistenceClientError else {
            return "That chat could not be renamed."
        }

        switch persistenceError {
        case .applicationSupportDirectoryUnavailable:
            return "That chat could not be renamed right now."
        case .corruptedRecord:
            return "That chat could not be renamed because chat history is corrupted."
        }
    }

    static func sessionDeleteFailureMessage(for error: Error) -> String {
        guard let persistenceError = error as? AiChatSessionPersistenceClientError else {
            return "That chat could not be deleted."
        }

        switch persistenceError {
        case .applicationSupportDirectoryUnavailable:
            return "That chat could not be deleted right now."
        case .corruptedRecord:
            return "That chat could not be deleted because chat history is corrupted."
        }
    }

    func sessionRestoreFailureMessage(for failure: AiChatSessionRestoreFailure) -> String {
        switch failure {
        case .missingRecord:
            return "That chat is no longer available."
        case .contextMismatch:
            return "That chat can no longer be restored with the current model context."
        case .corruptedRecord:
            return "That chat could not be restored because its saved data is corrupted."
        case .unsupportedVersion:
            return "That chat was saved in an unsupported format."
        case .unknown:
            return "That chat could not be restored."
        }
    }

    func attachmentSource(for url: URL) -> AiChatAttachmentSource {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "voycoll" {
            return .collectionDocument
        }
        if url.hasDirectoryPath {
            return .folder
        }
        return .file
    }
}

private extension String {
    var nilIfBlankForSessionRename: String? {
        isEmpty ? nil : self
    }
}

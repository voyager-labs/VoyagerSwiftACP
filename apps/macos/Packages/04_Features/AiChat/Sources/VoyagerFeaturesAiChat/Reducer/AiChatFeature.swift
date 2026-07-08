import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerShared

@Reducer
public struct AiChatFeature {
    public typealias State = AiChatState
    public typealias Action = AiChatAction

    enum CancelID: Hashable {
        case request(AiChatRequestID)
        case requestContextResolution(UUID)
        case requestStartPersistence(AiChatRequestID)
        case requestFinalPersistence(AiChatRequestID)
        case restore
        case persistenceRecovery
        case modelList
        case sessionList
        case sessionDelete
        case sessionRename
        case newChat
        case transcriptScrollOffsetPersistence
        case attachmentDrop
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
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.continuousClock)
    var clock

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                normalizeSelectionIfNeeded(&state)
                let capturedClient = userDefaultsClient
                return .run { send in
                    let offsets = _loadTranscriptScrollOffsets(
                        from: capturedClient,
                    )
                    await send(.transcriptScrollOffsetsLoaded(offsets))
                }

            case .sessionsAppeared:
                state.mode = .sessions
                state.sessionList.isLoading = true
                state.sessionList.errorMessage = nil
                return loadSessions()

            case .newChatTapped:
                let preservedExecutionPhase = state.executionPhase
                let snapshot = startNewUnselectedChat(state: &state)
                preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                return saveNewChat(snapshot)

            case .showSessionsTapped:
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.mode = .sessions
                guard let restoreSessionID = state.restoreSessionID, restoreSessionID != state.sessionID else {
                    return .none
                }
                state.restoreSessionID = nil
                return .cancel(id: CancelID.restore)

            case let .showSessionsForChat(sessionID):
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.mode = .sessions
                state.sessionID = sessionID
                state.sessionList.selectedSessionID = sessionID
                guard let restoreSessionID = state.restoreSessionID, restoreSessionID != sessionID else {
                    return .none
                }
                state.restoreSessionID = nil
                return .cancel(id: CancelID.restore)

            case .returnToChatTapped:
                if let restoreSessionID = state.restoreSessionID,
                   restoreSessionID != state.sessionID
                {
                    return .none
                }
                guard state.sessionID != nil else {
                    let preservedExecutionPhase = state.executionPhase
                    let snapshot = startNewUnselectedChat(state: &state)
                    preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                    return saveNewChat(snapshot)
                }
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.mode = .chat
                return .cancel(id: CancelID.restore)

            case let .routeToChatSession(sessionID):
                return routeToChatSession(sessionID, state: &state)

            case .startNewChatFromRebindTapped:
                let preservedExecutionPhase = state.executionPhase
                let snapshot = startNewUnselectedChat(state: &state)
                preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                return saveNewChat(snapshot)

            case .rebindContextTapped:
                state.sessionStatus = .active
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.unavailableSelectedModelHandle = nil
                normalizeSelectionIfNeeded(&state)
                return .none

            case let .sessionRowTapped(sessionID):
                return handleSessionRowTapped(sessionID: sessionID, state: &state)

            case let .deleteSessionTapped(sessionID):
                return handleDeleteSessionTapped(sessionID: sessionID, state: &state)

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
                refreshCustomTitleInExecutionOwners(
                    sessionID: summary.sessionID,
                    customTitle: customTitle,
                    state: &state,
                )
                if state.sessionID == summary.sessionID {
                    state.currentSessionCustomTitle = customTitle
                }
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                return .none

            case let .sessionRenameFailed(_, message):
                state.sessionList.errorMessage = message
                return .none

            case let .sessionSnapshotUpdated(summary, _, requestID, runID):
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

            case let .sessionSnapshotSaved(summary, snapshot, requestID, runID):
                applySessionSnapshotSaved(
                    summary: summary,
                    snapshot: snapshot,
                    requestID: requestID,
                    runID: runID,
                    state: &state,
                )
                return .none

            case .backToSessionsTapped:
                return handleBackToSessionsTapped(state: &state)

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
                state.pendingEmptyDraftDeletionSessionIDs.remove(sessionID)
                state.sessionList.removeRow(sessionID: sessionID)
                if state.restoreSessionID == sessionID {
                    state.restoreSessionID = nil
                    state.restoreOutcome = nil
                    state.restoreFailure = nil
                }
                return .none

            case let .sessionDeleteFailed(sessionID, message):
                state.pendingEmptyDraftDeletionSessionIDs.remove(sessionID)
                state.sessionList.errorMessage = message
                return .none

            case let .newChatCreated(snapshot):
                applyNewChatCreated(snapshot: snapshot, state: &state)
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
                if restoreSessionID == state.sessionID,
                   state.transcriptHistory.isEmpty,
                   state.sessionStatus == .idle
                {
                    // 새 ContentPane 채팅은 아직 저장된 세션이 없으므로 restore를 타지 않는다.
                    state.restoreSessionID = nil
                    return .none
                }
                state.sessionStatus = .restoring
                return restoreSession(sessionID: restoreSessionID, state: state)

            case let .providerConnectionsUpdated(file):
                return handleProviderConnectionsUpdated(file: file, state: &state)

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
                let currentContext = currentContextSnapshot(
                    snapshot,
                    excluding: state.addedAttachments,
                    applyingFolderStructureModes: state.currentContextFolderStructureModes,
                )
                ensureCurrentFolderStructureModeDefaults(
                    for: currentContext,
                    in: &state.currentContextFolderStructureModes,
                )
                state.currentContext = applyFolderStructureModes(
                    state.currentContextFolderStructureModes,
                    to: currentContext,
                )
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

            case let .attachmentDrop(providers):
                return loadDroppedAttachmentURLs(from: providers)

            case let .attachmentDropSelection(urls):
                let didAddAttachments = addAttachmentDrafts(
                    from: urls,
                    skippingCurrentContextDuplicates: false,
                    state: &state,
                )
                guard didAddAttachments else { return .none }
                removeCurrentContextDuplicates(state: &state)
                return .send(.delegate(.clearCurrentContextSelection))

            case let .removeAddedAttachment(id):
                removeAddedAttachment(id, state: &state)
                return .none

            case let .folderStructureModeChanged(target, mode):
                switch target {
                case .currentContext:
                    updateCurrentContextFolderStructureMode(mode, state: &state)
                case let .attachment(attachmentID):
                    guard let index = state.addedAttachments.firstIndex(where: { $0.id == attachmentID }) else {
                        return .none
                    }
                    guard state.addedAttachments[index].source == .folder else { return .none }
                    state.addedAttachments[index] = updateAttachmentFolderStructureMode(
                        mode,
                        for: state.addedAttachments[index],
                    )
                }
                return .none

            case .openSettingsTapped:
                return .send(.delegate(.openAISettings))

            case let .transcriptScrollOffsetsLoaded(offsets):
                state.transcriptScrollOffsets = offsets
                return .none

            case let .transcriptScrollOffsetChanged(sessionID, offsetY):
                state.transcriptScrollOffsets[sessionID] = max(0, offsetY)
                let snapshot = state.transcriptScrollOffsets
                let capturedClient = userDefaultsClient
                let capturedClock = clock
                return .run { _ in
                    try await capturedClock.sleep(for: .milliseconds(300))
                    _saveTranscriptScrollOffsets(snapshot, to: capturedClient)
                }
                .cancellable(id: CancelID.transcriptScrollOffsetPersistence, cancelInFlight: true)

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

            case let .requestContextResolved(resolutionID, resolvedContext):
                return completeRequestContextResolution(
                    resolutionID: resolutionID,
                    resolvedContext: resolvedContext,
                    state: &state,
                )

            case .cancelTapped:
                return handleCancelTapped(state: &state)

            case .resetTapped:
                return handleResetTapped(state: &state)

            case let .cancelRequestLifecycle(sessionID):
                return cancelRequestLifecycle(for: sessionID, state: &state) ?? .none

            case .cancelInFlightWork:
                return cancelAllInFlightWork(state: &state)

            case .teardownRequested:
                return handleTeardownRequested(state: &state)

            case let .restoreOutcome(requestedSessionID, result, restoreFailure):
                return handleRestoreOutcome(
                    requestedSessionID: requestedSessionID,
                    result: result,
                    restoreFailure: restoreFailure,
                    state: &state,
                )

            case let .executionEvent(event):
                return handleExecutionEvent(event, state: &state)

            case let .persistenceFailed(lock, failure):
                return handlePersistenceFailed(lock: lock, failure: failure, state: &state)

            case let .persistenceRecoverySucceeded(lock):
                return handlePersistenceRecoverySucceeded(lock: lock, state: &state)

            case let .persistenceRecoveryRetryFailed(lock, failure):
                return handlePersistenceRecoveryRetryFailed(lock: lock, failure: failure, state: &state)
            }
        }
    }
}

private let _transcriptScrollOffsetsKey = "voyager.aiChat.transcriptScrollOffsets"

private func _loadTranscriptScrollOffsets(
    from userDefaultsClient: UserDefaultsClient,
) -> [AiChatSessionID: CGFloat] {
    guard let storedOffsets = userDefaultsClient
        .object(_transcriptScrollOffsetsKey) as? [String: Double]
    else { return [:] }

    return storedOffsets.reduce(into: [AiChatSessionID: CGFloat]()) { result, element in
        guard let uuid = UUID(uuidString: element.key) else { return }
        result[AiChatSessionID(rawValue: uuid)] = CGFloat(max(0, element.value))
    }
}

private func _saveTranscriptScrollOffsets(
    _ offsets: [AiChatSessionID: CGFloat],
    to userDefaultsClient: UserDefaultsClient,
) {
    let storedOffsets = offsets.reduce(into: [String: Double]()) { result, element in
        result[element.key.rawValue.uuidString] = Double(max(0, element.value))
    }
    userDefaultsClient.setObject(storedOffsets, _transcriptScrollOffsetsKey)
}

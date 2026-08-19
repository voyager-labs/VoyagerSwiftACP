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
        case persistenceRecovery(AiChatRequestID)
        case modelList
        case sessionList
        case sessionDelete
        case sessionRename
        case newChat(ownerID: UUID)
        case transcriptScrollOffsetPersistence
        case attachmentDrop(AiChatSessionID)
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

    func matchesRequestLifecycleOwner(
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        state: State,
    ) -> Bool {
        if case let .processing(lock) = state.executionPhase,
           lock.requestID == requestID,
           lock.runID == runID
        {
            return true
        }
        return state.backgroundExecutionPhases[requestID]?.lock?.runID == runID
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            if invalidatesPendingNewChatPreparation(action, in: state) {
                state.newChatPreparationMutationTracker.value &+= 1
            }
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
                guard state.mode == .sessions else { return .none }
                state.sessionList.isLoading = true
                state.sessionList.errorMessage = nil
                return loadSessions()

            case .newChatTapped:
                return startNewChat(seed: nil, state: &state)

            case let .newChatTappedWithSeed(seed):
                return startNewChat(seed: seed, state: &state)

            case let .newChatTappedIfCurrent(provenance, seed):
                return startNewChatIfCurrent(provenance: provenance, seed: seed, state: &state)

            case .prepareUnpersistedNewChat:
                return prepareUnpersistedNewChat(currentContext: nil, seed: nil, state: &state)

            case let .prepareUnpersistedNewChatWithSeed(seed):
                return prepareUnpersistedNewChat(currentContext: nil, seed: seed, state: &state)

            case let .prepareTransientNewChat(sessionID, seed):
                return prepareTransientNewChat(sessionID: sessionID, seed: seed, state: &state)

            case let .prepareTransientNewChatIfCurrent(sessionID, provenance, seed):
                return prepareTransientNewChatIfCurrent(
                    sessionID: sessionID,
                    provenance: provenance,
                    seed: seed,
                    state: &state,
                )

            case let .prepareUnpersistedNewChatWithContext(snapshot):
                return prepareUnpersistedNewChat(currentContext: snapshot, seed: nil, state: &state)

            case let .prepareTransientNewChatWithContext(snapshot, seed):
                return prepareUnpersistedNewChat(currentContext: snapshot, seed: seed, state: &state)

            case let .prepareUnpersistedNewChatIfActive(snapshot, provenance, seed):
                guard state.newChatPreparationProvenance == provenance else { return .none }
                return prepareUnpersistedNewChat(currentContext: snapshot, seed: seed, state: &state)

            case let .applyNewChatSelectionSeedIfCurrent(provenance, seed):
                guard state.newChatPreparationProvenance == provenance else { return .none }
                let validatedSeed = AiChatStateSelection.revalidatedNewChatSelectionSeed(seed, state: state)
                state.selectedModelHandle = validatedSeed?.modelHandle
                state.selectedThinking = validatedSeed?.selectedThinking
                state.unavailableSelectedModelHandle = nil
                return .none

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
                state.settleCancelledSessionRestoreIfNeeded()
                return .cancel(id: CancelID.restore)

            case let .showSessionsForChat(sessionID):
                return state.prepareSessionsPresentation(for: sessionID)
                    ? .cancel(id: CancelID.restore)
                    : .none

            case .returnToChatTapped:
                if let restoreSessionID = state.restoreSessionID,
                   restoreSessionID != state.sessionID
                {
                    return .none
                }
                guard state.sessionID != nil else {
                    let preservedExecutionPhase = state.executionPhase
                    let snapshot = startNewUnselectedChat(seed: nil, state: &state)
                    preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                    return saveNewChat(snapshot, ownerID: state.cancellationOwnerID)
                }
                state.sessionList.cancelRenaming()
                state.sessionList.errorMessage = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.settleCancelledSessionRestoreIfNeeded()
                state.mode = .chat
                return .cancel(id: CancelID.restore)

            case let .routeToChatSession(sessionID):
                return routeToChatSession(sessionID, state: &state)

            case .startNewChatFromRebindTapped:
                let preservedExecutionPhase = state.executionPhase
                let snapshot = startNewUnselectedChat(seed: nil, state: &state)
                preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                return saveNewChat(snapshot, ownerID: state.cancellationOwnerID)

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
                guard !state.sessionList.deletedSessionIDs.contains(summary.sessionID),
                      matchesRequestLifecycleOwner(requestID: requestID, runID: runID, state: state)
                else { return .none }
                guard state.sessionList.replaceRowIfNewer(summary).acceptsRow else { return .none }
                if state.sessionID == summary.sessionID {
                    state.sessionList.selectedSessionID = summary.sessionID
                    state.sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
                }
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

            case .transcriptSearchOpened:
                state.transcriptSearch.isPresented = true
                state.transcriptSearch.focusRevision &+= 1
                return .none

            case .transcriptSearchClosed:
                state.transcriptSearch.reset()
                return .none

            case let .transcriptSearchQueryChanged(query):
                state.transcriptSearch.updateQuery(query)
                return .none

            case let .transcriptSearchMatchCountChanged(projection):
                state.transcriptSearch.updateMatchCount(projection)
                return .none

            case .transcriptSearchNextTapped:
                state.transcriptSearch.selectNextMatch()
                return .none

            case .transcriptSearchPreviousTapped:
                state.transcriptSearch.selectPreviousMatch()
                return .none

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
                    state.settleCancelledSessionRestoreIfNeeded()
                }
                return .none

            case let .sessionDeleteFailed(sessionID, message):
                state.pendingEmptyDraftDeletionSessionIDs.remove(sessionID)
                state.sessionList.errorMessage = message
                return .none

            case let .newChatCreated(snapshot):
                guard state.emptyDraftSessionID == snapshot.sessionID else { return .none }
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
                let previousSessionID = state.sessionID
                state.emptyDraftSessionID = nil
                state.currentSessionCustomTitle = nil
                apply(setup: setup, to: &state)
                normalizeSelectionIfNeeded(&state)
                let attachmentDropCancellation: Effect<Action> = if let previousSessionID,
                                                                    previousSessionID != state.sessionID
                {
                    .cancel(id: CancelID.attachmentDrop(previousSessionID))
                } else {
                    .none
                }
                guard let restoreSessionID = state.restoreSessionID else {
                    state.settleCancelledSessionRestoreIfNeeded()
                    return attachmentDropCancellation
                }
                if restoreSessionID == state.sessionID,
                   state.transcriptHistory.isEmpty,
                   state.sessionStatus == .idle
                {
                    // 새 ContentPane 채팅은 아직 저장된 세션이 없으므로 restore를 타지 않는다.
                    state.restoreSessionID = nil
                    return attachmentDropCancellation
                }
                state.beginSessionRestore(for: restoreSessionID)
                return .merge(
                    attachmentDropCancellation,
                    restoreSession(sessionID: restoreSessionID, state: state),
                )

            case let .providerConnectionsUpdated(file):
                return handleProviderConnectionsUpdated(file: file, state: &state)

            case let .providerConnectionAuthorityUpdated(connectedProviders):
                state.providerConnectionSnapshot = .known(connectedProviders)
                return .none

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

            case let .selectedModelChanged(handle):
                return handleSelectedModelChanged(handle, state: &state)

            case let .selectedThinkingChanged(selectedThinking):
                return handleSelectedThinkingChanged(selectedThinking, state: &state)

            case let .currentContextChanged(snapshot):
                let previousContext = state.currentContext
                let previousFolderStructureModes = state.currentContextFolderStructureModes
                applyCurrentContextSnapshot(snapshot, state: &state)
                if state.currentContext != previousContext
                    || state.currentContextFolderStructureModes != previousFolderStructureModes
                {
                    state.markPreparedTransientSessionAsTouched()
                }
                return .none

            case let .draftTextChanged(text):
                guard state.draftText != text else { return .none }
                state.markPreparedTransientSessionAsTouched()
                state.draftText = text
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case .attachmentPickerTapped:
                guard let sessionID = state.sessionID else { return .none }
                return .send(.delegate(.requestAttachmentPicker(sessionID)))

            case let .attachmentPickerSelection(originSessionID, urls):
                guard state.sessionID == originSessionID else { return .none }
                _ = addAttachmentDrafts(from: urls, skippingCurrentContextDuplicates: true, state: &state)
                return .none

            case let .attachmentDrop(originSessionID, providers):
                guard state.sessionID == originSessionID else { return .none }
                return loadDroppedAttachmentURLs(from: providers, originSessionID: originSessionID)

            case let .attachmentDropSelection(originSessionID, urls):
                guard state.sessionID == originSessionID else { return .none }
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
                    let updatedAttachment = updateAttachmentFolderStructureMode(
                        mode,
                        for: state.addedAttachments[index],
                    )
                    guard updatedAttachment != state.addedAttachments[index] else { return .none }
                    state.markPreparedTransientSessionAsTouched()
                    state.addedAttachments[index] = updatedAttachment
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

private func invalidatesPendingNewChatPreparation(
    _ action: AiChatAction,
    in state: AiChatFeature.State,
) -> Bool {
    switch action {
    case let .selectedModelChanged(handle):
        guard let handle else { return true }
        return state.normalizedSelectionHandle(handle) != nil
    case .selectedThinkingChanged,
         .currentContextChanged,
         .draftTextChanged,
         .removeAddedAttachment,
         .folderStructureModeChanged:
        return true
    case let .attachmentPickerSelection(originSessionID, _),
         let .attachmentDrop(originSessionID, _),
         let .attachmentDropSelection(originSessionID, _):
        return state.sessionID == originSessionID
    default:
        return false
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

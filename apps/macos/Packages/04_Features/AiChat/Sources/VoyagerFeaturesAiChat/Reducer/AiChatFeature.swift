import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiChatFeature {
    public typealias State = AiChatState
    public typealias Action = AiChatAction

    enum CancelID: Hashable {
        case request
        case requestContextResolution
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
                let preservedExecutionPhase = state.executionPhase
                let snapshot = startNewUnselectedChat(state: &state)
                preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
                return saveNewChat(snapshot)

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
                state.emptyDraftSessionID = nil
                state.sessionList.cancelRenaming()
                state.sessionList.selectedSessionID = sessionID
                state.sessionList.unreadCompletedSessionIDs.remove(sessionID)
                state.sessionList.errorMessage = nil
                if state.sessionID != sessionID {
                    state.currentContextFolderStructureModes = [:]
                }

                if state.executionPhase.isProcessing, state.sessionID == sessionID {
                    state.mode = .chat
                    return .none
                }

                state.mode = .sessions
                state.restoreSessionID = sessionID
                return restoreSession(sessionID: sessionID, state: state)

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
                            wasCancelled: true,
                        ))
                    }
                    preDeleteEffects.append(cancelRequestLifecycle())
                }
                guard !preDeleteEffects.isEmpty else {
                    return deleteSession(sessionID)
                }
                return .concatenate(
                    .merge(preDeleteEffects),
                    deleteSession(sessionID),
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
                let exitEffects: Effect<Action> = .cancel(id: CancelID.restore)
                if state.restoreSessionID != nil {
                    state.restoreSessionID = nil
                    state.restoreOutcome = nil
                    state.restoreFailure = nil
                }
                guard let emptyDraftSessionID = cleanupEligibleEmptyDraftSessionID(for: state) else {
                    return exitEffects
                }
                state.pendingEmptyDraftDeletionSessionIDs.insert(emptyDraftSessionID)
                state.emptyDraftSessionID = nil
                state.sessionID = nil
                state.restoreSessionID = nil
                state.restoreOutcome = nil
                state.restoreFailure = nil
                state.sessionList.selectedSessionID = nil
                state.sessionList.errorMessage = nil
                return .concatenate(
                    exitEffects,
                    deleteSession(emptyDraftSessionID),
                )

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
                            credential: loadRequest.credential,
                        ))
                    }),
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
                if state.pendingRequestStart != nil {
                    state.pendingRequestStart = nil
                    return .cancel(id: CancelID.requestContextResolution)
                }
                guard let lock = state.executionPhase.lock, state.executionPhase.isProcessing else { return .none }
                state.lockedModelHandle = nil
                state.streamingAssistantDraft = nil
                state.executionPhase = .cancelled(lock.recordingTerminal(
                    at: currentTimestampMs(),
                    failure: .cancelled,
                    wasCancelled: true,
                ))
                return cancelRequestLifecycle()

            case .resetTapped:
                state.pendingRequestStart = nil
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
                state.pendingRequestStart = nil
                state.streamingAssistantDraft = nil
                state.lockedModelHandle = nil
                state.executionPhase = .idle
                return cancelAllInFlightWork()

            case let .restoreOutcome(requestedSessionID, result, restoreFailure):
                guard state.restoreSessionID == requestedSessionID else { return .none }
                let isSessionListRestore = state.mode == .sessions && state.sessionList
                    .selectedSessionID == requestedSessionID
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
            .cancel(id: CancelID.requestContextResolution),
            .cancel(id: CancelID.requestStartPersistence),
            .cancel(id: CancelID.requestFinalPersistence),
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
            .cancel(id: CancelID.sessionRename),
        )
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
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

    func preserveNavigationExecutionPhase(
        _ executionPhase: AiChatExecutionPhase,
        state: inout State,
    ) {
        guard let lock = executionPhase.lock else { return }

        switch executionPhase {
        case .processing, .completed, .persistenceRecovery:
            state.backgroundExecutionPhases[lock.requestID] = executionPhase
            if state.executionPhase.requestID == lock.requestID {
                state.executionPhase = .idle
            }

        case .idle, .failed, .cancelled:
            break
        }
    }

    func startNewUnselectedChat(
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> AiChatSessionSnapshot {
        let sessionID = AiChatSessionID(rawValue: uuid())
        let validatedSeed = AiChatStateSelection.revalidatedNewChatSelectionSeed(seed, state: state)
        prepareEmptyDraftChatSession(sessionID, selectedSessionID: nil, seed: validatedSeed, state: &state)

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .idle,
            customTitle: nil,
            provider: validatedSeed?.modelHandle.provider,
            model: validatedSeed?.modelHandle,
            selectedModelRow: state.resolvedModelRow(for: validatedSeed?.modelHandle),
            selectedThinking: validatedSeed?.selectedThinking,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: currentTimestampMs(),
        )
    }

    func startNewChat(
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> Effect<Action> {
        let preservedExecutionPhase = state.executionPhase
        let snapshot = startNewUnselectedChat(seed: seed, state: &state)
        preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
        return saveNewChat(snapshot, ownerID: state.cancellationOwnerID)
    }

    func prepareUnpersistedNewChat(
        currentContext: AiChatCurrentContextSnapshot?,
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> Effect<Action> {
        movePendingRequestStartToBackgroundIfNeeded(state: &state, targetSessionID: nil)
        let preservedExecutionPhase = state.executionPhase
        let snapshot = startNewUnselectedChat(seed: seed, state: &state)
        state.emptyDraftSessionID = nil
        state.preparedTransientSessionID = snapshot.sessionID
        if let currentContext {
            applyCurrentContextSnapshot(currentContext, state: &state)
        }
        preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
        return .cancel(id: CancelID.newChat(ownerID: state.cancellationOwnerID))
    }

    func prepareTransientNewChat(
        sessionID: AiChatSessionID,
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> Effect<Action> {
        movePendingRequestStartToBackgroundIfNeeded(state: &state, targetSessionID: nil)
        let preservedExecutionPhase = state.executionPhase
        let validatedSeed = AiChatStateSelection.revalidatedNewChatSelectionSeed(seed, state: state)
        prepareEmptyDraftChatSession(sessionID, selectedSessionID: nil, seed: validatedSeed, state: &state)
        state.emptyDraftSessionID = nil
        state.preparedTransientSessionID = sessionID
        preserveNavigationExecutionPhase(preservedExecutionPhase, state: &state)
        return .cancel(id: CancelID.newChat(ownerID: state.cancellationOwnerID))
    }

    func startNewChatIfCurrent(
        provenance: AiChatNewChatPreparationProvenance,
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.newChatPreparationProvenance == provenance else { return .none }
        return startNewChat(seed: seed, state: &state)
    }

    func prepareTransientNewChatIfCurrent(
        sessionID: AiChatSessionID,
        provenance: AiChatNewChatPreparationProvenance,
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.newChatPreparationProvenance == provenance else { return .none }
        return prepareTransientNewChat(sessionID: sessionID, seed: seed, state: &state)
    }

    func saveNewChat(
        _ snapshot: AiChatSessionSnapshot,
        ownerID: UUID,
    ) -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                let persistedSnapshot = try await aiChatSessionPersistenceClient.saveSession(snapshot)
                await send(.newChatCreated(persistedSnapshot))
            } catch is CancellationError {
                return
            } catch {
                await send(.newChatFailed(Self.newChatFailureMessage(for: error)))
            }
        }
        .cancellable(id: CancelID.newChat(ownerID: ownerID), cancelInFlight: true)
    }

    func routeToChatSession(_ sessionID: AiChatSessionID, state: inout State) -> Effect<Action> {
        if state.prepareChatPresentation(for: sessionID) {
            return .cancel(id: CancelID.restore)
        }

        state.resetTranscriptSearchIfSessionChanges(to: sessionID)
        state.sessionList.cancelRenaming()
        state.sessionList.errorMessage = nil

        if state.restoreSessionID == sessionID {
            return .none
        }

        if state.beginDeferredChatSessionRestore(for: sessionID) {
            moveVisibleProcessingToBackgroundIfNeeded(state: &state, targetSessionID: sessionID)
            state.currentContextFolderStructureModes = [:]
            return restoreSession(sessionID: sessionID, state: state)
        }

        if state.sessionList.allRows.contains(where: { $0.sessionID == sessionID }) {
            if state.sessionID != sessionID {
                moveVisibleProcessingToBackgroundIfNeeded(state: &state, targetSessionID: sessionID)
                state.currentContextFolderStructureModes = [:]
            }
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.mode = .sessions
            return restoreSession(sessionID: sessionID, state: state)
        }

        prepareEmptyDraftChatSession(sessionID, selectedSessionID: sessionID, seed: nil, state: &state)
        return .cancel(id: CancelID.restore)
    }

    func prepareEmptyDraftChatSession(
        _ sessionID: AiChatSessionID,
        selectedSessionID: AiChatSessionID?,
        seed: AiChatNewChatSelectionSeed?,
        state: inout State,
    ) {
        state.invalidatePreparedTransientSession()
        state.resetTranscriptSearchIfSessionChanges(to: sessionID)
        state.sessionID = sessionID
        state.emptyDraftSessionID = sessionID
        state.sessionStatus = .idle
        state.mode = .chat
        state.restoreSessionID = nil
        state.currentSessionCustomTitle = nil
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionList.selectedSessionID = selectedSessionID
        state.sessionList.errorMessage = nil
        state.transcriptHistory = []
        state.draftText = ""
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = nil
        state.lastRequestContextModelHandle = nil
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
        state.executionPhase = .idle
        state.selectedModelHandle = seed?.modelHandle
        state.selectedThinking = seed?.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.resetInspectorReopenMutationBaseline(for: sessionID)
    }

    func renameSession(sessionID: AiChatSessionID, title: String) -> Effect<Action> {
        .run { [aiChatSessionPersistenceClient] send in
            do {
                guard let snapshot = try await aiChatSessionPersistenceClient.loadSession(sessionID) else {
                    await send(.sessionRenameFailed(sessionID, Self.sessionRenameFailureMessage(for: nil)))
                    return
                }
                let renamedSnapshot = Self.snapshot(snapshot, renamedTo: title, updatedAtMs: snapshot.updatedAtMs)
                let persistedSnapshot = try await aiChatSessionPersistenceClient.saveSession(renamedSnapshot)
                await send(.sessionRenameSucceeded(
                    AiChatSessionSummary(snapshot: persistedSnapshot),
                    customTitle: persistedSnapshot.customTitle,
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
        updatedAtMs: Int64,
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
            updatedAtMs: updatedAtMs,
        )
    }

    func refreshCustomTitleInExecutionOwners(
        sessionID: AiChatSessionID,
        customTitle: String?,
        state: inout State,
    ) {
        state.executionPhase = executionPhase(
            state.executionPhase,
            updatingCustomTitle: customTitle,
            for: sessionID,
        )
        for (requestID, phase) in state.backgroundExecutionPhases {
            state.backgroundExecutionPhases[requestID] = executionPhase(
                phase,
                updatingCustomTitle: customTitle,
                for: sessionID,
            )
        }
    }

    private func executionPhase(
        _ phase: AiChatExecutionPhase,
        updatingCustomTitle customTitle: String?,
        for sessionID: AiChatSessionID,
    ) -> AiChatExecutionPhase {
        guard phase.lock?.context.sessionID == sessionID else { return phase }
        switch phase {
        case .idle:
            return .idle
        case let .processing(lock):
            return .processing(lock.recordingCustomTitle(customTitle))
        case let .completed(lock):
            return .completed(lock.recordingCustomTitle(customTitle))
        case let .failed(lock, failure):
            return .failed(lock.recordingCustomTitle(customTitle), failure)
        case let .cancelled(lock):
            return .cancelled(lock.recordingCustomTitle(customTitle))
        case let .persistenceRecovery(lock, failure):
            return .persistenceRecovery(lock.recordingCustomTitle(customTitle), failure)
        }
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
            "That chat is no longer available."
        case .contextMismatch:
            "That chat can no longer be restored with the current model context."
        case .corruptedRecord:
            "That chat could not be restored because its saved data is corrupted."
        case .unsupportedVersion:
            "That chat was saved in an unsupported format."
        case .unknown:
            "That chat could not be restored."
        }
    }

    func handleDeleteSessionTapped(sessionID: AiChatSessionID, state: inout State) -> Effect<Action> {
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
        }
        let deletedSessionEffects = cancelRequestLifecycle(for: sessionID, state: &state)
        if let deletedSessionEffects {
            preDeleteEffects.append(deletedSessionEffects)
        }
        guard !preDeleteEffects.isEmpty else {
            return deleteSession(sessionID)
        }
        return .concatenate(
            .merge(preDeleteEffects),
            deleteSession(sessionID),
        )
    }

    func handleSessionRowTapped(sessionID: AiChatSessionID, state: inout State) -> Effect<Action> {
        state.resetTranscriptSearchIfSessionChanges(to: sessionID)
        state.emptyDraftSessionID = nil
        state.sessionList.cancelRenaming()
        state.sessionList.selectedSessionID = sessionID
        state.sessionList.unreadCompletedSessionIDs.remove(sessionID)
        state.sessionList.errorMessage = nil
        if state.sessionID != sessionID {
            moveVisibleProcessingToBackgroundIfNeeded(state: &state, targetSessionID: sessionID)
            state.currentContextFolderStructureModes = [:]
        }

        if state.executionPhase.isProcessing, state.sessionID == sessionID {
            state.mode = .chat
            return .none
        }

        state.mode = .sessions
        state.restoreSessionID = sessionID
        return restoreSession(sessionID: sessionID, state: state)
    }

    func handleBackToSessionsTapped(state: inout State) -> Effect<Action> {
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
        state.resetTranscriptSearchIfSessionChanges(to: nil)
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
    }

    func applySessionSnapshotSaved(
        summary: AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot?,
        requestID: AiChatRequestID?,
        runID: AiChatRunID?,
        state: inout State,
    ) {
        if let requestID {
            _ = state.completeInspectorReopenPersistenceBaseline(requestID: requestID)
        }
        if let requestID,
           let runID,
           let backgroundLock = state.backgroundExecutionPhases[requestID]?.lock,
           backgroundLock.runID == runID
        {
            state.backgroundExecutionPhases[requestID] = nil
        }
        let matchingCompletedLock: AiChatRequestLock? = if case let .completed(lock) = state.executionPhase,
                                                           lock.requestID == requestID,
                                                           lock.runID == runID
        {
            lock
        } else {
            nil
        }
        if let matchingCompletedLock {
            state.executionPhase = .completed(matchingCompletedLock.clearingFinalSnapshot())
        }
        guard !state.sessionList.deletedSessionIDs.contains(summary.sessionID) else { return }
        let mergeResult = state.sessionList.replaceRowIfNewer(summary)
        guard mergeResult.acceptsRow else { return }
        if mergeResult.permitsSnapshotPayload || matchingCompletedLock != nil,
           let snapshot,
           state.mode == .chat,
           state.sessionID == snapshot.sessionID
        {
            applyVisibleSavedSnapshot(snapshot, state: &state)
        }
        if state.restoreSessionID == nil || state.restoreSessionID == summary.sessionID {
            state.sessionList.selectedSessionID = summary.sessionID
        }
        if state.mode == .chat, state.sessionID == summary.sessionID {
            state.sessionList.unreadCompletedSessionIDs.remove(summary.sessionID)
        } else {
            state.sessionList.unreadCompletedSessionIDs.insert(summary.sessionID)
        }
        state.sessionList.errorMessage = nil
    }

    private func applyVisibleSavedSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        state: inout State,
    ) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = snapshot.status
        state.currentSessionCustomTitle = snapshot.customTitle
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = snapshot.lastRequestContext
        state.lastRequestContextModelHandle = snapshot.lastRequestContext == nil ? nil : snapshot.model
        state.transcriptAutoScrollVersion += 1
    }

    func applyNewChatCreated(snapshot: AiChatSessionSnapshot, state: inout State) {
        let selectedModelHandle = state.selectedModelHandle
        let selectedThinking = state.selectedThinking
        let unavailableSelectedModelHandle = state.unavailableSelectedModelHandle
        state.invalidatePreparedTransientSession()
        applyNewSessionSnapshot(snapshot, state: &state)
        state.selectedModelHandle = selectedModelHandle
        state.selectedThinking = selectedThinking
        state.unavailableSelectedModelHandle = unavailableSelectedModelHandle
        state.emptyDraftSessionID = snapshot.sessionID
        state.restoreSessionID = snapshot.sessionID
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.mode = .chat
        state.sessionList.selectedSessionID = snapshot.sessionID
        state.sessionList.errorMessage = nil
    }
}

private extension String {
    var nilIfBlankForSessionRename: String? {
        isEmpty ? nil : self
    }
}

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
        guard case .processing = executionPhase else { return }
        state.executionPhase = executionPhase
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
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
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
            updatedAtMs: currentTimestampMs(),
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

    func routeToChatSession(_ sessionID: AiChatSessionID, state: inout State) -> Effect<Action> {
        state.sessionList.cancelRenaming()
        state.sessionList.errorMessage = nil

        if state.sessionID == sessionID {
            if let restoreSessionID = state.restoreSessionID, restoreSessionID != sessionID {
                state.restoreSessionID = nil
                if state.sessionList.selectedSessionID == restoreSessionID {
                    state.sessionList.selectedSessionID = nil
                }
            }
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
            return .cancel(id: CancelID.restore)
        }

        if state.restoreSessionID == sessionID {
            return .none
        }

        if state.sessionList.allRows.contains(where: { $0.sessionID == sessionID }) {
            if state.sessionID != sessionID {
                state.currentContextFolderStructureModes = [:]
            }
            state.sessionList.selectedSessionID = sessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.restoreSessionID = sessionID
            state.mode = .sessions
            return restoreSession(sessionID: sessionID, state: state)
        }

        state.sessionID = sessionID
        state.emptyDraftSessionID = sessionID
        state.sessionStatus = .idle
        state.mode = .chat
        state.restoreSessionID = nil
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.currentSessionCustomTitle = nil
        state.sessionList.selectedSessionID = sessionID
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
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.unavailableSelectedModelHandle = nil
        return .cancel(id: CancelID.restore)
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
                    customTitle: renamedSnapshot.customTitle,
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
            preDeleteEffects.append(cancelRequestLifecycle())
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

    func applySessionSnapshotSaved(summary: AiChatSessionSummary, state: inout State) {
        guard !state.sessionList.deletedSessionIDs.contains(summary.sessionID) else { return }
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
    }

    func applyNewChatCreated(snapshot: AiChatSessionSnapshot, state: inout State) {
        applyNewSessionSnapshot(snapshot, state: &state)
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

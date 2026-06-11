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
}

private extension String {
    var nilIfBlankForSessionRename: String? {
        isEmpty ? nil : self
    }
}

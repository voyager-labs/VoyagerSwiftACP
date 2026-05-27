import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSessionNavigationTests: XCTestCase {
    func testInitialModeDefaultsToSessions() {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        XCTAssertEqual(store.state.mode, AiChatMode.sessions)
        XCTAssertEqual(store.state.sessionList, .init())
    }

    func testBackToSessionsPreservesActiveChatData() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let selectedSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let attachmentPath = "/tmp/Screenshot.png"
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: attachmentPath),
            source: .file,
            displayTitle: "Screenshot.png",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: URL(fileURLWithPath: attachmentPath),
                filePath: attachmentPath
            )
        )
        let transcript = [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi there")
        ]

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(
                rows: [makeSessionSummary(sessionID: selectedSessionID)],
                query: "release",
                isLoading: false,
                errorMessage: nil,
                selectedSessionID: selectedSessionID
            ),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            addedAttachments: [attachment],
            transcriptHistory: transcript,
            draftText: "Draft reply"
        )) {
            AiChatFeature()
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.sessionStatus, AiChatSessionStatus.active)
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.draftText, "Draft reply")
        XCTAssertEqual(store.state.addedAttachments, [attachment])
        XCTAssertEqual(store.state.sessionList.selectedSessionID, selectedSessionID)
    }

    func testNewChatTappedClearsStaleAddedAttachments() async {
        let staleAttachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: "/tmp/Stale.pdf"),
            source: .file,
            displayTitle: "Stale.pdf",
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Stale.pdf")
        )
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContextFolderStructureModesByCanonicalPath: [AiChatCurrentContextFolderStructureKey(source: .reference, canonicalPath: "/tmp/StaleFolder"): .includeSubfolders],
            addedAttachments: [staleAttachment]
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.newChatTapped) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
            state.sessionStatus = .idle
            state.mode = .chat
            state.restoreSessionID = nil
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
            state.currentContextFolderStructureModesByCanonicalPath = [:]
            state.executionPhase = .idle
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
        }

        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: newSessionID,
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
            updatedAtMs: 1_700_000_000_000
        )

        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            state.sessionID = newSessionID
            state.emptyDraftSessionID = newSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = nil
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.executionPhase = .idle
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.restoreSessionID = newSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.selectedSessionID = newSessionID
            state.sessionList.errorMessage = nil
        }
    }

    func testBackToSessionsDeletesUntouchedNewChatDraft() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                }
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.hiddenEmptyDraftSessionIDs, [sessionID])

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    func testBackToSessionsDeletesNewChatDraftAfterTypingWithoutSending() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                }
            )
        }

        await store.send(.draftTextChanged("Do not keep unsent draft")) { state in
            state.draftText = "Do not keep unsent draft"
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    func testBackToSessionsDeletesNewChatDraftAfterModelSelectionWithoutSending() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let model = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
            selectedModelHandle: model
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                }
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteSucceeded(sessionID)) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.allRows = []
            state.sessionList.rows = []
            state.sessionList.deletedSessionIDs = [sessionID]
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
    }

    func testBackToSessionsSurfacesEmptyDraftDeleteFailure() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                    throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable
                }
            )
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
            state.pendingEmptyDraftDeletionSessionIDs = [sessionID]
            state.emptyDraftSessionID = nil
            state.sessionID = nil
            state.restoreSessionID = nil
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = nil
        }

        await store.receive(.sessionDeleteFailed(sessionID, "That chat could not be deleted right now.")) { state in
            state.pendingEmptyDraftDeletionSessionIDs = []
            state.sessionList.errorMessage = "That chat could not be deleted right now."
        }

        XCTAssertEqual(deletedSessionIDs.value, [sessionID])
        XCTAssertEqual(store.state.sessionList.allRows, [summary])
    }

}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String = "Release notes follow-up",
    preview: String? = "Need the latest diff summary.",
    messageCount: Int = 2,
    contextTitle: String? = "Release docs",
    provider: AiProvider = .openai,
    model: AiModelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
    createdAtMs: Int64 = 1_000,
    updatedAtMs: Int64 = 2_000,
    status: AiChatSessionStatus = .active
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: preview,
        messageCount: messageCount,
        contextTitle: contextTitle,
        provider: provider,
        model: model,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
        status: status
    )
}

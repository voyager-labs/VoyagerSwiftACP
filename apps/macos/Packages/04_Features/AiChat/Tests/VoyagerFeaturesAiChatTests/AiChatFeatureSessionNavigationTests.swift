import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW005 spec-owner suite 밖에 남긴 session navigation empty-draft cleanup 회귀 테스트.
// back-to-sessions draft deletion/failure와 stale attachment reset contract를 보존한다.

@MainActor
final class AiChatFeatureSessionNavigationTests: XCTestCase {
    /// 초기 AiChat mode가 sessions로 시작하는지 검증
    func testInitialModeDefaultsToSessions() {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        XCTAssertEqual(store.state.mode, AiChatMode.sessions)
        XCTAssertEqual(store.state.sessionList, .init())
    }

    /// new chat 시작 시 stale added attachments가 정리되는지 검증
    func testNewChatTappedClearsStaleAddedAttachments() async {
        let staleAttachment = makeNavigationAttachment(path: "/tmp/Stale.pdf")
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            currentContextFolderStructureModes: [
                makeNavigationFolderKey("/tmp/StaleFolder"): .includeSubfolders,
            ],
            addedAttachments: [staleAttachment],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        await store.send(.newChatTapped) { state in
            applyNavigationNewChatStarted(&state, sessionID: newSessionID)
        }

        let expectedSnapshot = makeNavigationEmptySnapshot(sessionID: newSessionID)
        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            applyNavigationNewChatCreated(&state, snapshot: expectedSnapshot)
        }
    }

    /// 수정하지 않은 new chat draft에서 sessions로 돌아가면 draft가 삭제되는지 검증
    func testBackToSessionsDeletesUntouchedNewChatDraft() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
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

    /// 입력만 하고 전송하지 않은 new chat draft가 sessions 복귀 시 삭제되는지 검증
    func testBackToSessionsDeletesNewChatDraftAfterTypingWithoutSending() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
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

    /// model 선택만 한 new chat draft가 sessions 복귀 시 삭제되는지 검증
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
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
            selectedModelHandle: model,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                },
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

    /// empty draft 삭제 실패가 sessions 화면에 error로 표시되는지 검증
    func testBackToSessionsSurfacesEmptyDraftDeleteFailure() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let summary = makeSessionSummary(sessionID: sessionID, status: .idle)
        let deletedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionList: .init(
                allRows: [summary],
                selectedSessionID: sessionID,
            ),
            sessionID: sessionID,
            emptyDraftSessionID: sessionID,
            sessionStatus: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { sessionID in
                    deletedSessionIDs.withValue { $0.append(sessionID) }
                    throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable
                },
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
    createdAtMs: Int64 = 1000,
    updatedAtMs: Int64 = 2000,
    status: AiChatSessionStatus = .active,
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
        status: status,
    )
}

private func makeNavigationAttachment(path: String) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: path),
        source: .file,
        displayTitle: URL(fileURLWithPath: path).lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: path),
    )
}

private func makeNavigationFolderKey(_ path: String) -> AiChatCurrentContextFolderStructureKey {
    AiChatCurrentContextFolderStructureKey(source: .reference, canonicalPath: path)
}

private func applyNavigationNewChatStarted(
    _ state: inout AiChatFeature.State,
    sessionID: AiChatSessionID,
) {
    applySessionListNewChatStarted(&state, sessionID: sessionID)
    state.addedAttachments = []
    state.currentContextFolderStructureModes = [:]
}

private func applyNavigationNewChatCreated(
    _ state: inout AiChatFeature.State,
    snapshot: AiChatSessionSnapshot,
) {
    applySessionListNewChatCreated(&state, snapshot: snapshot)
    state.addedAttachments = []
}

private func makeNavigationEmptySnapshot(sessionID: AiChatSessionID) -> AiChatSessionSnapshot {
    makeSessionListEmptySnapshot(sessionID: sessionID, updatedAtMs: 1_700_000_000_000)
}

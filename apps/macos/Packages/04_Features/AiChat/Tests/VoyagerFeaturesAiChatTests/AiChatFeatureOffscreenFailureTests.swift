import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// navigation 중 offscreen request failure가 현재 session UI를 오염시키지 않는지 보존한다.

@MainActor
final class AiChatFeatureOffscreenFailureTests: XCTestCase {
    // 다른 session을 열람하는 동안 원 request 실패가 현재 session 화면을 오염시키지 않는지 검증
    // swiftlint:disable:next function_body_length
    func testOffscreenRequestFailureDoesNotPolluteVisibleSessionAndRestoresOriginalFailure() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111241"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222241"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_241
        let activeRow = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Active request",
            preview: "Question A",
            messageCount: 1,
            contextTitle: "Docs",
            provider: selectedHandle.provider,
            model: selectedHandle,
            createdAtMs: fixedMs - 10,
            updatedAtMs: fixedMs - 10,
            status: .active,
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Earlier target chat")],
            updatedAtMs: fixedMs - 1,
        )
        let targetRow = AiChatSessionSummary(snapshot: targetSnapshot)
        let activeRestoreSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A")],
            updatedAtMs: fixedMs,
        )
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { id in
            switch id {
            case targetSessionID:
                targetSnapshot
            case activeSessionID:
                activeRestoreSnapshot
            default:
                nil
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [activeRow, targetRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question A",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { try await persistence.loadSession($0) },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Question A")]
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .processing(lock)
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertNil(store.state.requestStatusText)

        stream.yield(.failed(context: request.context, reason: .network))
        stream.finish()

        let failedLock = lock.recordingTerminal(at: fixedMs, failure: .network, wasCancelled: false)
        await store.receive(.executionEvent(.failed(context: request.context, reason: .network))) { state in
            state.lockedModelHandle = nil
            state.executionPhase = .failed(failedLock, .network)
        }
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.transcriptHistory, targetSnapshot.transcriptHistory)
        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertNil(store.state.requestStatusText)
        if case .processing = store.state.surfaceState {
            XCTFail("The visible target session must not show another session's failed request as processing")
        }

        await store.send(.sessionRowTapped(activeSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.restoreSessionID = activeSessionID
            state.currentContextFolderStructureModes = [:]
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: activeSessionID,
            .restored(snapshot: activeRestoreSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRestoreSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRestoreSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .failed(failedLock, .network)
            state.selectedModelHandle = activeRestoreSnapshot.model
            state.selectedThinking = activeRestoreSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRestoreSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.requestStatusText, AiChatExecutionFailure.network.displayMessage)
        XCTAssertEqual(persistence.snapshots.count, 1)
        await store.finish()
    }
}

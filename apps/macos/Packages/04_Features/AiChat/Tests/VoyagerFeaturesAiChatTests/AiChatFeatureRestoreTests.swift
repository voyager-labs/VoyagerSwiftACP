import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW005 spec-owner suite로 이관하지 않은 restore recovery 회귀 테스트.
// missing record fallback, rebind submit guard, empty catalog behavior 같은 edge contract를 보존한다.

@MainActor
final class AiChatFeatureRestoreTests: XCTestCase {
    /// 누락된 session record restore가 오류 없이 새 session fallback으로 전환되는지 검증
    func testRestoreMissingRecordFallsBackToNewSessionWithoutError() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in nil })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        let staleTranscript = [AiChatMessage(role: .user, content: "stale")]
        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: staleTranscript,
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = staleTranscript
            state.draftText = "Draft"
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = catalogRows[1].handle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [],
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .missingRecord
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.sessionStatusText, "Started new session")
        XCTAssertTrue(store.state.canSubmit)
        XCTAssertEqual(store.state.transcriptHistory, [])
        XCTAssertEqual(store.state.transcriptAutoScrollVersion, 0)
    }

    /// 빈 catalog에서 누락 session fallback이 unknown model selection을 노출하지 않는지 검증
    func testRestoreMissingRecordWithEmptyCatalogDoesNotExposeUnknownModelSelection() async {
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999"))
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in nil })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }

        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "Draft",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .missingRecord
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedModelDisplayModel)
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.restoreFailure, .missingRecord)
        XCTAssertEqual(store.state.sessionStatus, .idle)
    }

    /// rebind required 상태에서는 선택 model이 유효해도 submit이 차단되는지 검증
    func testRebindRequiredBlocksSubmitEvenWhenSelectionIsOtherwiseValid() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionStatus: .rebindRequired,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
        )

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
    }

    /// rebind 상태에서 새 chat 시작 시 durable unselected snapshot이 저장되는지 검증
    func testStartNewChatFromRebindTappedSavesDurableUnselectedSnapshot() async {
        let catalogRows = makeCatalogRows()
        let newSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = TestStore(initialState: AiChatFeature.State(
            restoreFailure: .contextMismatch,
            sessionStatus: .rebindRequired,
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_000))
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.startNewChatFromRebindTapped) { state in
            applySessionListNewChatStarted(&state, sessionID: newSessionID)
        }

        let expectedSnapshot = makeSessionListEmptySnapshot(
            sessionID: newSessionID,
            updatedAtMs: 1_700_000_000_000,
        )
        await store.receive(.newChatCreated(expectedSnapshot)) { state in
            applySessionListNewChatCreated(&state, snapshot: expectedSnapshot)
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
    }
}

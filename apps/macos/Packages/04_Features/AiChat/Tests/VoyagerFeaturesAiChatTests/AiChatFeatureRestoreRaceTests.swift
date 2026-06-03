import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureRestoreRaceTests: XCTestCase {
    func testRestoreOutcomeFromSupersededSessionIsIgnored() async {
        let catalogRows = makeCatalogRows()
        let currentRestoreSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let staleRestoreSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let currentTranscript = [AiChatMessage(role: .user, content: "current draft context")]
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: staleRestoreSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale restore")],
            updatedAtMs: 0
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: currentRestoreSessionID,
            sessionID: nil,
            sessionStatus: .restoring,
            currentContext: makeContextSnapshot(summary: "Current restore"),
            transcriptHistory: currentTranscript,
            draftText: "Current draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )) {
            AiChatFeature()
        }

        await store.send(.restoreOutcome(
            requestedSessionID: staleRestoreSessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil
        ))

        XCTAssertEqual(store.state.restoreSessionID, currentRestoreSessionID)
        XCTAssertNil(store.state.sessionID)
        XCTAssertEqual(store.state.sessionStatus, .restoring)
        XCTAssertEqual(store.state.transcriptHistory, currentTranscript)
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
        XCTAssertNil(store.state.restoreOutcome)
        XCTAssertNil(store.state.restoreFailure)
    }

    func testLateSnapshotSavedDoesNotStealSelectionDuringSessionRestore() async {
        let catalogRows = makeCatalogRows()
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let activeSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Previous prompt"),
                AiChatMessage(role: .assistant, content: "Late final")
            ],
            updatedAtMs: 2_000
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [AiChatMessage(role: .user, content: "Target session")],
            updatedAtMs: 1_500
        )
        let activeSummary = AiChatSessionSummary(snapshot: activeSnapshot)
        let targetSummary = AiChatSessionSummary(snapshot: targetSnapshot)
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: targetSessionID,
            mode: .sessions,
            sessionList: .init(
                allRows: [targetSummary, activeSummary],
                selectedSessionID: targetSessionID
            ),
            sessionID: activeSessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        }

        await store.send(AiChatAction.sessionSnapshotSaved(activeSummary)) { state in
            state.sessionList.replaceRow(activeSummary)
            state.sessionList.unreadCompletedSessionIDs.insert(activeSessionID)
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.sessionList.selectedSessionID, targetSessionID)

        await store.send(AiChatAction.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.currentSessionCustomTitle = targetSnapshot.customTitle
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.executionPhase = .idle
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.unavailableSelectedModelHandle = nil
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.mode, AiChatMode.chat)
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.sessionList.selectedSessionID, targetSessionID)
    }

}

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
}

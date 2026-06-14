import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureTerminalSurfaceStateTests: XCTestCase {
    func testTerminalSurfaceIgnoresLegacySessionStatusErrorWithoutRestoreFlow() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let failedSessionState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock),
        )

        if case let .ready(summary, selectedModel) = failedSessionState.surfaceState {
            XCTAssertFalse(summary.isEmpty)
            XCTAssertEqual(selectedModel?.handle, selectedHandle)
        } else {
            XCTFail("Expected terminal surface to remain ready when restore flow is disabled")
        }
        if case .ready = failedSessionState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected skeleton surface to remain ready when restore flow is disabled")
        }
        XCTAssertTrue(failedSessionState.canSubmit)
        XCTAssertNil(failedSessionState.sessionStatusText)
    }

    func testPersistenceRecoverySurfaceReflectsExecutionFailure() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let recoveryState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Recovered locally")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )

        if case let .error(connection, summary) = recoveryState.surfaceState {
            XCTAssertEqual(connection.title, "Chat unavailable")
            XCTAssertEqual(connection.detail, "An unknown chat error occurred.")
            XCTAssertFalse(summary.isEmpty)
        } else {
            XCTFail("Expected persistence recovery to surface execution error")
        }
        if case let .error(connection) = recoveryState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(connection.fixLabel, "Retry")
        } else {
            XCTFail("Expected skeleton surface to expose persistence recovery error")
        }
        XCTAssertEqual(recoveryState.requestStatusText, "Finalized locally; An unknown chat error occurred.")
        XCTAssertFalse(recoveryState.canSubmit)
    }
}

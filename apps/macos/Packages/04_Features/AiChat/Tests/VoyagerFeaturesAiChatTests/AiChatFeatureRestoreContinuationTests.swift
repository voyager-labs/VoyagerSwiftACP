import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureRestoreContinuationTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testRestoreValidSessionRestoresTranscriptAndNormalizesLockedState() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .anthropic,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Restored answer")
            ],
            lastRequestID: AiChatRequestID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666")),
            lastRunID: AiChatRunID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777")),
            updatedAtMs: 0
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        let staleLock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: targetSessionID,
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: catalogRows[1].handle,
                    selectedRow: catalogRows[1]
                ),
                messages: []
            ),
            selectedHandle: catalogRows[1].handle,
            selectedRow: catalogRows[1],
            assistantReplacementIndex: nil
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .restoring,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError,
            executionPhase: .processing(staleLock)
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = [AiChatMessage(role: .assistant, content: "stale")]
            state.draftText = "Draft"
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = catalogRows[1].handle
            state.lastExecutionFailure = .transportError
            state.executionPhase = .idle
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: restoredSnapshot),
            restoreFailure: nil
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
            state.selectedModelHandle = restoredSnapshot.model
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertEqual(store.state.transcriptHistory, restoredSnapshot.transcriptHistory)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertEqual(store.state.sessionStatusText, "Restored session")
    }

    // swiftlint:disable:next function_body_length
    func testRestoreFallsBackToFirstCurrentModelWhenRestoredModelIsMissing() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "missing-model"),
            selectedModelRow: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            updatedAtMs: 0
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: restoredSnapshot.model,
            lockedModelHandle: nil,
            lastExecutionFailure: nil
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let normalizedSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: restoredSnapshot.transcriptHistory,
            lastRequestID: nil,
            lastRunID: nil,
            updatedAtMs: 0
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: normalizedSnapshot),
            restoreFailure: nil
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
            state.selectedModelHandle = normalizedSnapshot.model
            state.restoreOutcome = .restored(snapshot: normalizedSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows.first?.handle)
        XCTAssertEqual(store.state.modelCatalogState.selectedModel?.handle, catalogRows.first?.handle)
    }
}

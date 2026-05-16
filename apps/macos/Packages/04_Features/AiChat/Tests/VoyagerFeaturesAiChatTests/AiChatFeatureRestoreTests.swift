import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureRestoreTests: XCTestCase {
    // swiftlint:disable:next function_body_length
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
                deleteSession: { _ in }
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
            lastExecutionFailure: nil
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
            updatedAtMs: 0
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord
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
    }

    // swiftlint:disable:next function_body_length
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
                deleteSession: { _ in }
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
            lastExecutionFailure: nil
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

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .failed(reason: .missingRecord),
            restoreFailure: .missingRecord
        )) { state in
            state.sessionStatus = .failed
            state.restoreFailure = .missingRecord
            state.restoreOutcome = nil
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedModelDisplayModel)
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.restoreFailure, .missingRecord)
        XCTAssertEqual(store.state.sessionStatus, .failed)
    }

    // swiftlint:disable:next function_body_length
    func testRestoreContextMismatchFailsWithoutFallbackModelSelection() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444"))
        let rebindSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .rebindRequired,
            provider: .anthropic,
            model: AiModelHandle(provider: .anthropic, rawValue: "stale-model"),
            selectedModelRow: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            updatedAtMs: 0
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in rebindSnapshot })
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
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: rebindSnapshot.model,
            lockedModelHandle: rebindSnapshot.model,
            lastExecutionFailure: nil
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
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = rebindSnapshot.model
            state.lockedModelHandle = rebindSnapshot.model
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .failed(reason: .contextMismatch),
            restoreFailure: .contextMismatch
        )) { state in
            state.sessionStatus = .failed
            state.restoreFailure = .contextMismatch
            state.restoreOutcome = nil
            state.unavailableSelectedModelHandle = rebindSnapshot.model
        }

        XCTAssertEqual(store.state.restoreFailure, .contextMismatch)
        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .assistant, content: "stale")])
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, rebindSnapshot.model)
    }
}

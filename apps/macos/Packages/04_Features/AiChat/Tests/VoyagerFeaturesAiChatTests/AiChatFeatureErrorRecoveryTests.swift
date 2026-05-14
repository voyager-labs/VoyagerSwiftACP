import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureErrorRecoveryTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testErrorRecoveryRetriesPersistenceSaveAndClearsRecoveryState() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
                runID: AiChatRunID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
                model: selectedHandle,
                selectedRow: catalogRows[0]
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")]
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )
        let transcript = [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi")
        ]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: transcript,
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown)
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in }
            )
        }

        await store.send(.errorRecoveryTapped)

        await store.receive(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.sessionID, sessionID)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, transcript)
        await store.finish()
    }

    // swiftlint:disable:next function_body_length
    func testErrorRecoveryRetriesFailedSessionRestore() async {
        let catalogRows = makeCatalogRows()
        let restoreSessionID = AiChatSessionID(rawValue: makeUUID("66666666-6666-6666-6666-666666666666"))
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: restoreSessionID,
            status: .active,
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Restored")],
            updatedAtMs: 0
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: restoreSessionID,
            sessionID: nil,
            sessionStatus: .failed,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { sessionID in
                    XCTAssertEqual(sessionID, restoreSessionID)
                    return restoredSnapshot
                },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
        }

        await store.send(.errorRecoveryTapped) { state in
            state.sessionStatus = .restoring
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: restoreSessionID,
            .restored(snapshot: restoredSnapshot),
            restoreFailure: nil
        )) { state in
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
            state.sessionID = restoreSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.draftText = "Draft"
            state.selectedModelHandle = catalogRows[0].handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        await store.finish()
    }

    func testPersistenceRecoveryIgnoresRetryFailureAfterSuccess() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("88888888-8888-8888-8888-888888888888")),
                runID: AiChatRunID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999")),
                model: selectedHandle,
                selectedRow: catalogRows[0]
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")]
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown)
        )) {
            AiChatFeature()
        }

        await store.send(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        await store.send(.persistenceRecoveryRetryFailed(lock, .unknown))

        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertEqual(store.state.executionPhase, .completed(lock))
        await store.finish()
    }

    func testErrorRecoveryDelegatesOpenSettingsForRebindRequiredSession() async {
        let catalogRows = makeCatalogRows()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionStatus: .rebindRequired,
            currentContext: makeContextSnapshot(),
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .idle
        )) {
            AiChatFeature()
        }

        await store.send(.errorRecoveryTapped)
        await store.receive(.delegate(.openAISettings))
        await store.finish()
    }
}

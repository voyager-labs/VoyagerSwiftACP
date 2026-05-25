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

        let fallbackSessionID = AiChatSessionID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
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

    // swiftlint:disable:next function_body_length
    func testRestoreContextMismatchEntersRebindRequiredRecoveryState() async {
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

        let normalizedSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: rebindSnapshot.provider,
            model: rebindSnapshot.model,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: rebindSnapshot.transcriptHistory,
            lastRequestContext: nil,
            updatedAtMs: rebindSnapshot.updatedAtMs
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .rebindRequired(snapshot: normalizedSnapshot),
            restoreFailure: .contextMismatch
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .rebindRequired
            state.transcriptHistory = rebindSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = nil
            state.lastRequestContextModelHandle = nil
            state.executionPhase = .idle
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.restoreOutcome = .rebindRequired(snapshot: normalizedSnapshot)
            state.restoreFailure = .contextMismatch
            state.unavailableSelectedModelHandle = rebindSnapshot.model
        }

        XCTAssertEqual(store.state.restoreFailure, .contextMismatch)
        XCTAssertEqual(store.state.transcriptHistory, rebindSnapshot.transcriptHistory)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, rebindSnapshot.model)
        XCTAssertEqual(store.state.sessionStatusText, "Session needs rebind")
    }
    func testSessionRowRestoreFailureKeepsSessionsModeAndShowsOneTimeError() async {
        let catalogRows = makeCatalogRows()
        let existingSessionID = AiChatSessionID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999"))
        let requestedSessionID = AiChatSessionID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555"))
        let staleTranscript = [AiChatMessage(role: .assistant, content: "already open chat")]
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in nil })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(rows: [AiChatSessionSummary(
                sessionID: requestedSessionID,
                title: "Broken session",
                preview: "Can't restore",
                messageCount: 1,
                contextTitle: "Docs",
                provider: catalogRows[1].handle.provider,
                model: catalogRows[1].handle,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active
            )]),
            sessionID: existingSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current"),
            transcriptHistory: staleTranscript,
            draftText: "Keep me",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle
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

        await store.send(.sessionRowTapped(requestedSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = requestedSessionID
            state.sessionList.errorMessage = nil
            state.restoreSessionID = requestedSessionID
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
            requestedSessionID: requestedSessionID,
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord
        )) { state in
            state.sessionList.selectedSessionID = nil
            state.sessionList.errorMessage = "That chat is no longer available."
        }

        XCTAssertEqual(store.state.mode, .sessions)
        XCTAssertEqual(store.state.sessionID, existingSessionID)
        XCTAssertEqual(store.state.transcriptHistory, staleTranscript)
        XCTAssertEqual(store.state.draftText, "Keep me")
        XCTAssertNil(store.state.restoreOutcome)
        XCTAssertNil(store.state.restoreFailure)
    }


    func testRebindRequiredBlocksSubmitEvenWhenSelectionIsOtherwiseValid() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionStatus: .rebindRequired,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: catalogRows[1].handle
        )

        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
    }

    func testRebindContextTappedClearsRecoveryStateAndPreservesTranscript() async {
        let catalogRows = makeCatalogRows()
        let transcript = [AiChatMessage(role: .user, content: "old")]
        let staleHandle = AiModelHandle(provider: .anthropic, rawValue: "stale-model")
        let store = TestStore(initialState: AiChatFeature.State(
            restoreFailure: .contextMismatch,
            sessionStatus: .rebindRequired,
            transcriptHistory: transcript,
            draftText: "follow up",
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: nil,
            unavailableSelectedModelHandle: staleHandle
        )) {
            AiChatFeature()
        }

        await store.send(.rebindContextTapped) { state in
            state.sessionStatus = .active
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.unavailableSelectedModelHandle = nil
        }

        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertNil(store.state.selectedModelHandle)
    }

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
            selectedModelHandle: catalogRows[1].handle
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
                deleteSession: { _ in }
            )
        }

        await store.send(.startNewChatFromRebindTapped) { state in
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
            state.executionPhase = .idle
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
        }

        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: newSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
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

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
        XCTAssertNil(store.state.selectedModelHandle)
    }

}

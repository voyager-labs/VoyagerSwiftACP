import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureTests: XCTestCase {
    func testSetupBuildsUnconnectedEntryStateWithContextSummary() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()

        await store.send(.setup(AiChatSetupState(
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.sessionID = nil
            state.sessionStatus = .idle
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.title, "Four files selected")
        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.detail, "1 reference · 1 item · 1 attachment")
        XCTAssertEqual(store.state.connectionState, .unconnected(.init(
            title: "No session connected",
            detail: "Start or open a session to continue from the current context.",
            fixLabel: "Open session",
        )))

        if case let .unconnected(connection, summaryDisplay) = store.state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open session")
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
        } else {
            XCTFail("Expected unconnected surface state")
        }

        XCTAssertEqual(store.state.modelFieldLabel, "Model")
        XCTAssertEqual(store.state.modelCatalogState.rows.first?.label.title, "GPT-4.1 Mini")
        XCTAssertEqual(
            store.state.modelCatalogState.rows.first?.label.subtitle,
            ProviderDescriptor.descriptor(for: catalogRows[0].handle.provider)?.displayName,
        )
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
    }

    func testCurrentContextSummaryFixturesMatchInspectorContract() {
        let selectedHandle = makeCatalogRows()[0].handle

        let selectedEntriesState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Documents · 2 selected",
                references: [],
                items: [],
                attachments: [],
            ),
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(selectedEntriesState.currentContextSummaryDisplayModel.title, "Documents · 2 selected")
        XCTAssertNil(selectedEntriesState.currentContextSummaryDisplayModel.detail)

        let locationOnlyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(locationOnlyState.currentContextSummaryDisplayModel.title, "Documents")
        XCTAssertNil(locationOnlyState.currentContextSummaryDisplayModel.detail)

        let emptyContextState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current context")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    func testProviderUnavailableSurfaceUsesSettingsFixtureAndDisablesSubmit() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        XCTAssertEqual(state.connectionState, .error(.init(
            title: "No AI provider connected",
            detail: "Connect an AI provider in Settings to start chatting.",
            fixLabel: "Connect provider in Settings",
        )))
        XCTAssertFalse(state.canSubmit)

        if case let .error(connection, summary) = state.surfaceState {
            XCTAssertEqual(connection.title, "No AI provider connected")
            XCTAssertEqual(connection.detail, "Connect an AI provider in Settings to start chatting.")
            XCTAssertEqual(connection.fixLabel, "Connect provider in Settings")
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected provider unavailable error surface")
        }
    }

    func testCanSubmitDisallowsRetryWhileFailureSurfaceExists() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry after failure",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .idle,
        )
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    func testSubmitTappedIsNoOpWhenCanSubmitIsFalse() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(requestSpy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)

        await store.finish()
    }

    func testSurfaceStateCoversEmptyReadyProcessingAndError() {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let selectedHandle = catalogRows[0].handle

        let emptyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case .empty = emptyState.surfaceState {
        } else {
            XCTFail("Expected empty surface state")
        }

        let currentContextInitialState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .empty(summaryDisplay, selectedModel) = currentContextInitialState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected current-context initial chat to use empty surface state")
        }

        let readyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .ready(summaryDisplay, selectedModel) = readyState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected ready surface state")
        }

        let processingState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "Streaming",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: catalogRows[1].handle,
                        selectedRow: catalogRows[1],
                    ),
                    messages: [],
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil,
            )),
        )

        if case let .processing(processing, _, selectedModel) = processingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.cancelAffordance.title, "Cancel request")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected processing surface state")
        }

        let errorState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
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
            ), .transportError),
        )

        if case let .error(connection, _) = errorState.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Retry")
        } else {
            XCTFail("Expected error surface state")
        }
    }

    func testModelSelectionIsNextRequestOnlyAndSameModelIsNoOp() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let placeholderRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: catalogRows[0].handle,
                selectedRow: catalogRows[0],
            ),
            messages: [],
        )
        let placeholderLock = makeRequestLock(
            kind: .submit,
            request: placeholderRequest,
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[0].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(placeholderLock),
        )) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(catalogRows[0].handle))

        await store.send(.selectedModelChanged(catalogRows[1].handle)) { state in
            state.selectedModelHandle = catalogRows[1].handle
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[0].handle)

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing surface state")
        }

        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.executionPhase = .cancelled(placeholderLock)
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[1].handle)
    }

    func testSetupFallsBackToFirstCatalogRowWhenSelectedModelIsUnresolvable() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let unresolvableHandle = makeUnresolvableModelHandle()
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.setup(AiChatSetupState(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: unresolvableHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows.first?.handle)
        XCTAssertEqual(store.state.modelCatalogState.selectedModel?.handle, catalogRows.first?.handle)

        if case let .empty(summaryDisplay, selectedModel) = store.state.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.handle, catalogRows.first?.handle)
        } else {
            XCTFail("Expected initial empty surface state after fallback")
        }
    }

    func testRestoreMissingRecordFallsBackToNewSessionWithoutError() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
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
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows[1].handle
            state.lockedModelHandle = catalogRows[1].handle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
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
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .missingRecord,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .missingRecord
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows[1].handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.sessionStatusText, "Started new session")
        XCTAssertTrue(store.state.canSubmit)
        XCTAssertEqual(store.state.transcriptHistory, [])
    }

    func testRestoreContextMismatchFallsBackToNewSession() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let rebindSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .rebindRequired,
            provider: .anthropic,
            model: AiModelHandle(provider: .anthropic, rawValue: "stale-model"),
            selectedModelRow: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "old")],
            updatedAtMs: 0,
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in rebindSnapshot })
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
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: rebindSnapshot.model,
            lockedModelHandle: rebindSnapshot.model,
            lastExecutionFailure: nil,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = [AiChatMessage(role: .assistant, content: "stale")]
            state.draftText = "Draft"
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = rebindSnapshot.model
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let fallbackSessionID = AiChatSessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        let fallbackSnapshot = AiChatSessionSnapshot(
            sessionID: fallbackSessionID,
            status: .idle,
            provider: catalogRows.first?.handle.provider ?? .openai,
            model: catalogRows.first?.handle ?? AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            selectedModelRow: catalogRows.first,
            transcriptHistory: [],
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            .newSession(snapshot: fallbackSnapshot),
            restoreFailure: .contextMismatch,
        )) { state in
            state.restoreOutcome = .newSession(snapshot: fallbackSnapshot)
            state.restoreFailure = .contextMismatch
            state.sessionID = fallbackSessionID
            state.sessionStatus = .idle
            state.transcriptHistory = []
            state.draftText = "Draft"
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.restoreFailure, .contextMismatch)
        XCTAssertEqual(store.state.transcriptHistory, [])
    }

    func testRestoreValidSessionRestoresTranscriptAndNormalizesLockedState() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .anthropic,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Restored answer"),
            ],
            lastRequestID: AiChatRequestID(rawValue: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
            lastRunID: AiChatRunID(rawValue: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!),
            updatedAtMs: 0,
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
                    selectedRow: catalogRows[1],
                ),
                messages: [],
            ),
            selectedHandle: catalogRows[1].handle,
            selectedRow: catalogRows[1],
            assistantReplacementIndex: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .restoring,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            streamDraftText: "stale stream",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError,
            executionPhase: .processing(staleLock),
        )) {
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
            transcriptHistory: [AiChatMessage(role: .assistant, content: "stale")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: .transportError,
        ))) { state in
            state.restoreSessionID = targetSessionID
            state.restoreOutcome = nil
            state.restoreFailure = nil
            state.sessionID = nil
            state.sessionStatus = .restoring
            state.currentContext = summary
            state.transcriptHistory = [AiChatMessage(role: .assistant, content: "stale")]
            state.draftText = "Draft"
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = catalogRows[1].handle
            state.lastExecutionFailure = .transportError
            state.executionPhase = .idle
        }

        await store.receive(.restoreOutcome(.restored(snapshot: restoredSnapshot), restoreFailure: nil)) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.streamDraftText = ""
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
            state.selectedModelHandle = restoredSnapshot.model
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertEqual(store.state.transcriptHistory, restoredSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.lockedModelHandle, nil)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertEqual(store.state.sessionStatusText, "Restored session")
    }

    func testRestoreFallsBackToFirstCurrentModelWhenRestoredModelIsMissing() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "missing-model"),
            selectedModelRow: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            updatedAtMs: 0,
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
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
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: restoredSnapshot.model,
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
            state.draftText = ""
            state.streamDraftText = ""
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
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(.restored(snapshot: normalizedSnapshot), restoreFailure: nil)) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.streamDraftText = ""
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

    func testSelectedModelChangedFallsBackToFirstCatalogRowWithoutMutatingLockedModel() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let unresolvableHandle = makeUnresolvableModelHandle()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: sessionID,
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: catalogRows[1].handle,
                        selectedRow: catalogRows[1],
                    ),
                    messages: [],
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil,
            )),
        )) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(unresolvableHandle)) { state in
            state.selectedModelHandle = catalogRows.first?.handle
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[1].handle)
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows.first?.handle)

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected processing surface state after fallback")
        }
    }

    func testDraftTextChangeClearsStaleFailureAndResetStillClearsTranscript() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "Partial",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
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
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.draftTextChanged("Updated")) { state in
            state.draftText = "Updated"
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)

        await store.send(.resetTapped) { state in
            state.draftText = ""
            state.transcriptHistory = []
            state.streamDraftText = ""
            state.lastExecutionFailure = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        await store.finish()
    }

    func testSelectedModelChangeClearsStaleFailureAndRestoresSubmitEligibility() async {
        let catalogRows = makeCatalogRows()
        let firstHandle = catalogRows[0].handle
        let secondHandle = catalogRows[1].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry me",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: firstHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: firstHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: firstHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.selectedModelChanged(secondHandle)) { state in
            state.selectedModelHandle = secondHandle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)
        await store.finish()
    }

    func testSubmitStreamsDraftOnlyAndFinalizesExactlyOnce() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.streamDraftText = ""
            state.selectedModelHandle = selectedHandle
            state.lockedModelHandle = selectedHandle
            state.lastExecutionFailure = nil
            XCTAssertEqual(state.sessionID, sessionID)
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

        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello")])
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        stream.yield(.streamChunk(context: request.context, delta: "Hel"))
        await store.receive(.executionEvent(.streamChunk(context: request.context, delta: "Hel"))) { state in
            state.streamDraftText = "Hel"
        }

        stream.yield(.streamChunk(context: request.context, delta: "lo"))
        await store.receive(.executionEvent(.streamChunk(context: request.context, delta: "lo"))) { state in
            state.streamDraftText = "Hello"
        }

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hello back"),
            completedAtMs: 0,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.streamDraftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hello back"),
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock)
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory.count, 2)
        XCTAssertEqual(persistence.snapshots.first?.lastRequestID, request.context.requestID)
        XCTAssertEqual(persistence.snapshots.first?.lastRunID, request.context.runID)
    }

    func testCancelRejectsLateStreamAndFinalEvents() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Cancel me",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Cancel me")]
            state.lockedModelHandle = selectedHandle
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

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.streamDraftText = ""
            state.executionPhase = .cancelled(lock)
        }

        await store.send(.executionEvent(.streamChunk(context: request.context, delta: "late")))
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late final"),
            completedAtMs: 0,
        ))))

        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .user, content: "Cancel me")])
        XCTAssertEqual(store.state.streamDraftText, "")
        XCTAssertEqual(store.state.lockedModelHandle, nil)
        XCTAssertEqual(store.state.executionPhase, .cancelled(lock))

        await store.finish()
    }

    func testRegenerateReplacesAssistantWithoutDuplicatingUserTurn() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111113")!)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Old answer"),
            ],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped) { state in
            state.lockedModelHandle = selectedHandle
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .regenerate,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: 1,
        )

        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello")])
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "New answer"),
            completedAtMs: 0,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "New answer"),
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock)
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "New answer"),
        ])
    }

    func testPersistenceFailureCreatesRecoveryState() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111114")!)

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in
                    struct PersistenceBoom: Error {}
                    throw PersistenceBoom()
                },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
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

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi"),
            completedAtMs: 0,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.streamDraftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi"),
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock)
        }

        await store.receive(.persistenceFailed(lock, .unknown)) { state in
            state.lastExecutionFailure = .unknown
            state.executionPhase = .persistenceRecovery(lock, .unknown)
        }

        XCTAssertEqual(store.state.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi"),
        ])
        XCTAssertEqual(store.state.requestStatusText, "Finalized locally; An unknown chat error occurred.")

        await store.finish()
    }

    private func makeCatalogRows() -> [AiModelCatalogRow] {
        [
            AiModelCatalogRow(
                handle: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
                displayName: "GPT-4.1 Mini",
                authMethod: .apiKey,
                subtitle: nil,
                sortOrder: 10,
                isDefault: true,
                isRecommended: true,
            ),
            AiModelCatalogRow(
                handle: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
                displayName: "Claude Sonnet 4",
                authMethod: .apiKey,
                subtitle: "Reasoning-first chat",
                sortOrder: 20,
                isDefault: false,
                isRecommended: false,
            ),
        ]
    }

    private func makeUnresolvableModelHandle() -> AiModelHandle {
        AiModelHandle(provider: .openai, rawValue: "unresolvable-model")
    }

    private func makeContextSnapshot(
        summary: String = "Four files selected",
        references: [AiChatContextReference] = [
            AiChatContextReference(
                kind: .reference,
                identifier: "ref-1",
                title: "Readme.md",
                subtitle: "Project readme",
                metadata: ["path": "docs/Readme.md"],
            ),
        ],
        items: [AiChatContextItem] = [
            AiChatContextItem(
                kind: .file,
                identifier: "file-1",
                title: "VoyagerEntitiesAi.swift",
                subtitle: "Source file",
                metadata: ["path": "Sources/VoyagerEntitiesAi/VoyagerEntitiesAi.swift"],
            ),
        ],
        attachments: [AiChatContextAttachment] = [
            AiChatContextAttachment(
                identifier: "attachment-1",
                title: "Screenshot",
                subtitle: "Current state",
                metadata: ["mimeType": "image/png"],
            ),
        ],
    ) -> AiChatCurrentContextSnapshot {
        AiChatCurrentContextSnapshot(
            summary: summary,
            references: references,
            items: items,
            attachments: attachments,
        )
    }

    private func makeRequestContext(
        sessionID: AiChatSessionID,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        model: AiModelHandle,
        selectedRow: AiModelCatalogRow,
        promptSummary: String = "Hello",
    ) -> AiChatRequestContextSnapshot {
        AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: model.provider,
            model: model,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            promptSummary: promptSummary,
            submittedAtMs: nil,
        )
    }

    private func makeRequestLock(
        kind: AiChatRequestKind,
        request: AiChatRequest,
        selectedHandle: AiModelHandle,
        selectedRow: AiModelCatalogRow,
        assistantReplacementIndex: Int?,
    ) -> AiChatRequestLock {
        AiChatRequestLock(
            kind: kind,
            requestID: request.context.requestID,
            runID: request.context.runID,
            context: request.context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: selectedRow,
            assistantReplacementIndex: assistantReplacementIndex,
        )
    }
}

private final class AiChatExecutionStreamDriver: @unchecked Sendable {
    private(set) var requests: [AiChatRequest] = []
    private var continuations: [AsyncStream<AiChatEvent>.Continuation] = []

    func stream(for request: AiChatRequest) -> AsyncStream<AiChatEvent> {
        requests.append(request)
        return AsyncStream { continuation in
            self.continuations.append(continuation)
        }
    }

    func yield(_ event: AiChatEvent, at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].yield(event)
    }

    func finish(at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].finish()
    }
}

private final class AiChatSessionPersistenceSpy: @unchecked Sendable {
    private(set) var snapshots: [AiChatSessionSnapshot] = []
    private let loadHandler: @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?

    init(loadHandler: @escaping @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot? = { _ in nil }) {
        self.loadHandler = loadHandler
    }

    func loadSession(_ sessionID: AiChatSessionID) async throws -> AiChatSessionSnapshot? {
        try await loadHandler(sessionID)
    }

    func save(_ snapshot: AiChatSessionSnapshot) async {
        snapshots.append(snapshot)
    }
}

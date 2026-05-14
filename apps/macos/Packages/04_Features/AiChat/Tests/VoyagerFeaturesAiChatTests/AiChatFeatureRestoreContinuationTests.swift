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
            selectedThinking: .effort(.minimal),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Restored answer"),
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
            selectedThinking: .effort(.minimal),
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
            selectedThinking: .effort(.minimal),
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
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[0].handle
            state.selectedThinking = .effort(.minimal)
            state.unavailableSelectedModelHandle = nil
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
            state.selectedThinking = restoredSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertEqual(store.state.transcriptHistory, restoredSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.selectedThinking, restoredSnapshot.selectedThinking)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertEqual(store.state.sessionStatusText, "Restored session")
    }

    // swiftlint:disable:next function_body_length
    func testRestoreUsesCurrentCatalogRowMetadataWhenRestoredHandleStillResolves() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("88888888-8888-8888-8888-888888888888"))
        let staleSelectedRow = AiModelCatalogRow(
            handle: catalogRows[1].handle,
            displayName: "Old Claude Label",
            authMethod: .apiKey,
            subtitle: "Old provider subtitle",
            sortOrder: 999,
            isDefault: false,
            isRecommended: false
        )
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: staleSelectedRow,
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
            selectedModelHandle: catalogRows[0].handle,
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
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        let normalizedSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
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

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[1].handle)
        XCTAssertEqual(store.state.selectedModelDisplayModel?.title, catalogRows[1].displayName)
        guard case let .restored(snapshot) = store.state.restoreOutcome else {
            return XCTFail("Expected restored snapshot outcome")
        }
        XCTAssertEqual(snapshot.selectedModelRow, catalogRows[1])
    }

    // swiftlint:disable:next function_body_length
    func testRestoreClearsSelectionWhenRestoredModelIsMissing() async {
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
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = restoredSnapshot.model
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
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
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = restoredSnapshot.model
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, restoredSnapshot.model)
        XCTAssertNil(store.state.modelCatalogState.selectedModel)
        XCTAssertFalse(store.state.canSubmit)
    }

    // swiftlint:disable:next function_body_length
    func testRestoreClearsIncompatibleThinkingWhenConcreteModelCapabilitiesLoad() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("12121212-1212-1212-1212-121212121212"))
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .anthropic,
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)]
        )
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .anthropic,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            selectedThinking: .effort(.high),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            updatedAtMs: 0
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        let models = makeThinkingCapableProviderModels()
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { _ in },
                deleteSession: { _ in }
            )
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in models })
        }

        await store.send(.setup(AiChatSetupState(
            restoreSessionID: targetSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.high),
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
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = .effort(.high)
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
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
            state.selectedThinking = restoredSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.selectedThinking = nil
            state.modelListRequestID = requestID
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = [.anthropic]
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .anthropic,
            credential: anthropicCredential
        ))
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models
        )) { state in
            state.catalogRows = catalogRows
            state.modelListState = .loaded(models)
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [.anthropic: models]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[1].handle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertNil(store.state.unavailableSelectedModelHandle)
    }
}

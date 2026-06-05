// swiftlint:disable file_length
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW004 spec-owner suite 밖에 남긴 model selection reducer 회귀 테스트.
// provider update selection 보존/해제와 Codex execution path contract를 보존한다.

// swiftlint:disable type_body_length
@MainActor
final class AiChatFeatureSelectionTests: XCTestCase {
    /// teardown 요청이 processing draft를 중단하되 conversation은 유지하는지 검증
    func testTeardownRequestedStopsProcessingDraftWithoutClearingConversation() async {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111122"))
        let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000004"))
        let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000005"))
        let messages = [AiChatMessage(role: .user, content: "Keep this transcript")]
        let lock = makeTeardownProcessingLock(
            sessionID: sessionID,
            requestIDs: (requestID: requestID, runID: runID),
            catalogRow: catalogRows[0],
            selectedModel: models[0],
            summary: summary,
            messages: messages,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: messages,
            draftText: "Draft survives close",
            streamingAssistantDraft: "Partial response",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: catalogRows[0].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(lock),
        )) {
            AiChatFeature()
        }

        await store.send(.teardownRequested) { state in
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.transcriptHistory, messages)
        XCTAssertEqual(store.state.draftText, "Draft survives close")
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
    }

    /// Codex model 선택이 CLI execution path로 submit 가능한지 검증
    func testCodexModelSelectionCanSubmitThroughCLIExecutionPath() {
        let handle = AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5-codex")
        let row = AiModelCatalogRow(
            handle: handle,
            displayName: "GPT-5 Codex",
            authMethod: .oauth,
            subtitle: "Codex CLI",
            sortOrder: 10,
            isDefault: true,
            isRecommended: true,
        )
        let model = AiProviderModel(
            id: handle,
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            displayName: "GPT-5 Codex",
            providerDisplayName: "ChatGPT Codex",
            thinkingCapability: .effort(values: [.medium], defaultValue: .medium),
            unavailableReason: nil,
        )
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111121")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            draftText: "Run Codex",
            catalogRows: [row],
            modelListState: .loaded([model]),
            selectedModelHandle: handle,
            executionPhase: .idle,
            providerConnectionSnapshot: .known([.chatgptCodex]),
        )

        XCTAssertTrue(state.canSubmit)
        XCTAssertNil(state.requestStatusText)
    }

    /// 기존 model handle이 유지될 때 catalog row display name이 갱신되는지 검증
    func testCatalogRowsRefreshDisplayNameWhenExistingHandleIsPreserved() {
        let handle = AiModelHandle(provider: .openai, rawValue: "gpt-5.4-mini")
        let staleRow = AiModelCatalogRow(
            handle: handle,
            displayName: "gpt-5.4-mini",
            authMethod: .apiKey,
            subtitle: "Existing subtitle",
            sortOrder: 42,
            isDefault: true,
            isRecommended: true,
        )
        let refreshedModel = AiProviderModel(
            id: handle,
            provider: .openai,
            rawModelID: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unknown(reason: .init(message: "Metadata pending")),
            unavailableReason: nil,
        )

        let rows = AiChatFeature.State.makeCatalogRows(for: [refreshedModel], preserving: [staleRow])

        XCTAssertEqual(rows.map(\.handle), [handle])
        XCTAssertEqual(rows.map(\.displayName), ["GPT-5.4 Mini"])
        XCTAssertEqual(rows.first?.subtitle, "Existing subtitle")
        XCTAssertEqual(rows.first?.sortOrder, 42)
        XCTAssertEqual(rows.first?.isDefault, true)
        XCTAssertEqual(rows.first?.isRecommended, true)
    }

    // provider connection 갱신 후에도 유효한 현재 선택 model이 유지되는지 검증
    // swiftlint:disable:next function_body_length
    func testProviderConnectionsUpdatedPreservesValidCurrentSelection() async {
        let catalogRows = makeCatalogRows()
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
            lastUsedProviderId: .anthropic,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in
                [makeProviderModels()[1]]
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.selectedThinking = nil
            state.modelListRequestID = makeUUID("00000000-0000-0000-0000-000000000000")
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = [.anthropic]
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: makeUUID("00000000-0000-0000-0000-000000000000"),
            provider: .anthropic,
            credential: anthropicCredential,
        ))
        await store.receive(.modelListLoaded(
            requestID: makeUUID("00000000-0000-0000-0000-000000000000"),
            provider: .anthropic,
            models: [makeProviderModels()[1]],
        )) { state in
            state.catalogRows = [catalogRows[1]]
            state.modelListState = .loaded([makeProviderModels()[1]])
            state.selectedModelHandle = catalogRows[1].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [.anthropic: [makeProviderModels()[1]]]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[1].handle)
    }

    // provider connection 갱신 후 현재 선택 model이 사라지면 선택이 정리되는지 검증
    // swiftlint:disable:next function_body_length
    func testProviderConnectionsUpdatedClearsSelectionWhenCurrentModelDisappears() async {
        let catalogRows = makeCatalogRows()
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
            lastUsedProviderId: .anthropic,
        )
        let remainingModel = makeProviderModels()[1]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in
                [remainingModel]
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = makeUUID("00000000-0000-0000-0000-000000000000")
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = [.anthropic]
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: makeUUID("00000000-0000-0000-0000-000000000000"),
            provider: .anthropic,
            credential: anthropicCredential,
        ))
        await store.receive(.modelListLoaded(
            requestID: makeUUID("00000000-0000-0000-0000-000000000000"),
            provider: .anthropic,
            models: [remainingModel],
        )) { state in
            state.catalogRows = [catalogRows[1]]
            state.modelListState = .loaded([remainingModel])
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = catalogRows[0].handle
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [.anthropic: [remainingModel]]
            state.lastExecutionFailure = nil
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, catalogRows[0].handle)
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertFalse(store.state.canSubmit)
    }

    /// setup이 model selection 누락 상태를 자동 선택으로 보정하지 않는지 검증
    func testSetupDoesNotAutoSelectWhenSelectionIsMissing() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
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
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.modelCatalogState.selectedModel)
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertFalse(store.state.canSubmit)
    }
}

private func makeTeardownProcessingLock(
    sessionID: AiChatSessionID,
    requestIDs: (requestID: AiChatRequestID, runID: AiChatRunID),
    catalogRow: AiModelCatalogRow,
    selectedModel: AiProviderModel,
    summary: AiChatCurrentContextSnapshot,
    messages: [AiChatMessage],
) -> AiChatRequestLock {
    let context = AiChatRequestContextSnapshot(
        sessionID: sessionID,
        requestID: requestIDs.requestID,
        runID: requestIDs.runID,
        provider: catalogRow.handle.provider,
        model: catalogRow.handle,
        selectedModel: selectedModel,
        selectedModelRow: catalogRow,
        selectedThinking: .effort(.medium),
        sessionStatus: .active,
        currentContext: summary,
        promptSummary: "Keep this transcript",
        submittedAtMs: 1_700_000_000_600,
    )
    let request = AiChatRequest(context: context, messages: messages)

    return AiChatRequestLock(
        kind: .submit,
        requestID: requestIDs.requestID,
        runID: requestIDs.runID,
        context: context,
        request: request,
        selectedModelHandle: catalogRow.handle,
        selectedModelRow: catalogRow,
        assistantReplacementIndex: nil,
        historyTruncation: AiChatHistoryTruncationMetadata(
            includedMessageCount: 1,
            excludedMessageCount: 0,
            budget: 24000,
            truncationReason: nil,
        ),
        observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: 1_700_000_000_600),
    )
}

// swiftlint:enable type_body_length

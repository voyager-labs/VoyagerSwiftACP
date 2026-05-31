// swiftlint:disable file_length
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class AiChatFeatureSelectionTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testModelSelectionIsNextRequestOnlyAndSameModelIsNoOp() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let firstSubmitMs: Int64 = 1_700_000_000_600
        let secondSubmitMs: Int64 = 1_700_000_000_601
        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: firstSubmitMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
            let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000001"))
            let context = AiChatRequestContextSnapshot(
                sessionID: sessionID,
                requestID: requestID,
                runID: runID,
                provider: catalogRows[0].handle.provider,
                model: catalogRows[0].handle,
                selectedModel: models[0],
                selectedModelRow: catalogRows[0],
                selectedThinking: .effort(.medium),
                sessionStatus: .active,
                currentContext: summary,
                promptSummary: "Draft",
                submittedAtMs: firstSubmitMs,
            )
            let request = AiChatRequest(
                context: context,
                messages: [
                    AiChatMessage(role: .user, content: "Hello"),
                    AiChatMessage(role: .user, content: "Draft"),
                ],
            )
            let processingSummary = AiChatSessionSummary(
                sessionID: sessionID,
                title: "Draft",
                preview: "Draft",
                messageCount: 1,
                contextTitle: summary.summary,
                searchText: "Draft",
                provider: catalogRows[0].handle.provider,
                model: catalogRows[0].handle,
                createdAtMs: firstSubmitMs,
                updatedAtMs: firstSubmitMs,
                status: .active,
            )
            state.transcriptHistory = request.messages
            state.draftText = ""
            state.sessionList.allRows = [processingSummary]
            state.sessionList.rows = [processingSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
            state.executionPhase = .processing(AiChatRequestLock(
                kind: .submit,
                requestID: requestID,
                runID: runID,
                context: context,
                request: request,
                selectedModelHandle: catalogRows[0].handle,
                selectedModelRow: catalogRows[0],
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 2,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
                observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: firstSubmitMs),
            ))
        }

        XCTAssertEqual(requestSpy.requests.count, 1)
        XCTAssertEqual(requestSpy.requests[0].context.model, catalogRows[0].handle)
        XCTAssertEqual(requestSpy.requests[0].context.provider, catalogRows[0].handle.provider)
        XCTAssertEqual(requestSpy.requests[0].context.selectedModel, models[0])
        XCTAssertEqual(requestSpy.requests[0].context.selectedThinking, .effort(.medium))

        await store.send(.selectedModelChanged(catalogRows[0].handle))

        XCTAssertEqual(requestSpy.requests.count, 1)
        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[0].handle)

        await store.send(.selectedModelChanged(catalogRows[1].handle)) { state in
            state.selectedModelHandle = catalogRows[1].handle
            state.unavailableSelectedModelHandle = nil
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[0].handle)
        if case let .processing(lock) = store.state.executionPhase {
            XCTAssertEqual(lock.selectedModelHandle, catalogRows[0].handle)
            XCTAssertEqual(lock.context.model, catalogRows[0].handle)
            XCTAssertEqual(lock.context.provider, catalogRows[0].handle.provider)
            XCTAssertEqual(lock.context.selectedModel, models[0])
            XCTAssertEqual(lock.context.selectedThinking, .effort(.medium))
        } else {
            XCTFail("Expected request to remain locked while processing")
        }

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing surface state")
        }

        await store.send(.resetTapped) { state in
            state.draftText = ""
            state.transcriptHistory = []
            state.lastExecutionFailure = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        await store.send(.draftTextChanged("Second request")) { state in
            state.draftText = "Second request"
        }

        store.dependencies.date = .constant(makeFixedDate(milliseconds: secondSubmitMs))

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000002"))
            let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000003"))
            let context = AiChatRequestContextSnapshot(
                sessionID: sessionID,
                requestID: requestID,
                runID: runID,
                provider: catalogRows[1].handle.provider,
                model: catalogRows[1].handle,
                selectedModel: models[1],
                selectedModelRow: catalogRows[1],
                selectedThinking: .effort(.medium),
                sessionStatus: .active,
                currentContext: summary,
                promptSummary: "Second request",
                submittedAtMs: secondSubmitMs,
            )
            let request = AiChatRequest(
                context: context,
                messages: [AiChatMessage(role: .user, content: "Second request")],
            )
            let processingSummary = AiChatSessionSummary(
                sessionID: sessionID,
                title: "Second request",
                preview: "Second request",
                messageCount: 1,
                contextTitle: summary.summary,
                searchText: "Second request",
                provider: catalogRows[1].handle.provider,
                model: catalogRows[1].handle,
                createdAtMs: secondSubmitMs,
                updatedAtMs: secondSubmitMs,
                status: .active,
            )
            state.transcriptHistory = request.messages
            state.draftText = ""
            state.sessionList.allRows = [processingSummary]
            state.sessionList.rows = [processingSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.lockedModelHandle = catalogRows[1].handle
            state.transcriptAutoScrollVersion = 2
            state.executionPhase = .processing(AiChatRequestLock(
                kind: .submit,
                requestID: requestID,
                runID: runID,
                context: context,
                request: request,
                selectedModelHandle: catalogRows[1].handle,
                selectedModelRow: catalogRows[1],
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
                observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: secondSubmitMs),
            ))
        }

        XCTAssertEqual(requestSpy.requests.count, 2)
        XCTAssertEqual(requestSpy.requests[1].context.model, catalogRows[1].handle)
        XCTAssertEqual(requestSpy.requests[1].context.provider, catalogRows[1].handle.provider)
        XCTAssertEqual(requestSpy.requests[1].context.selectedModel, models[1])
        XCTAssertEqual(requestSpy.requests[1].context.selectedThinking, .effort(.medium))
    }

    // swiftlint:disable:next function_body_length
    func testTeardownRequestedStopsProcessingDraftWithoutClearingConversation() async {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111122"))
        let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000004"))
        let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000005"))
        let messages = [AiChatMessage(role: .user, content: "Keep this transcript")]
        let context = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: catalogRows[0].handle.provider,
            model: catalogRows[0].handle,
            selectedModel: models[0],
            selectedModelRow: catalogRows[0],
            selectedThinking: .effort(.medium),
            sessionStatus: .active,
            currentContext: summary,
            promptSummary: "Keep this transcript",
            submittedAtMs: 1_700_000_000_600,
        )
        let request = AiChatRequest(context: context, messages: messages)
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: catalogRows[0].handle,
            selectedModelRow: catalogRows[0],
            assistantReplacementIndex: nil,
            historyTruncation: AiChatHistoryTruncationMetadata(
                includedMessageCount: 1,
                excludedMessageCount: 0,
                budget: 24000,
                truncationReason: nil,
            ),
            observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: 1_700_000_000_600),
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

    // swiftlint:disable:next function_body_length
    func testSelectedThinkingChangedUpdatesDisplayModelAndNextRequestContext() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let firstSubmitMs: Int64 = 1_700_000_000_600
        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Use high thinking",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: firstSubmitMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "default")

        await store.send(.selectedThinkingChanged(.effort(.high))) { state in
            state.selectedThinking = .effort(.high)
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "high")

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000000"))
            let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000001"))
            let context = AiChatRequestContextSnapshot(
                sessionID: sessionID,
                requestID: requestID,
                runID: runID,
                provider: catalogRows[0].handle.provider,
                model: catalogRows[0].handle,
                selectedModel: models[0],
                selectedModelRow: catalogRows[0],
                selectedThinking: .effort(.high),
                sessionStatus: .active,
                currentContext: summary,
                promptSummary: "Use high thinking",
                submittedAtMs: firstSubmitMs,
            )
            let request = AiChatRequest(
                context: context,
                messages: [
                    AiChatMessage(role: .user, content: "Hello"),
                    AiChatMessage(role: .user, content: "Use high thinking"),
                ],
            )
            let processingSummary = AiChatSessionSummary(
                sessionID: sessionID,
                title: "Use high thinking",
                preview: "Use high thinking",
                messageCount: 1,
                contextTitle: summary.summary,
                searchText: "Use high thinking",
                provider: catalogRows[0].handle.provider,
                model: catalogRows[0].handle,
                createdAtMs: firstSubmitMs,
                updatedAtMs: firstSubmitMs,
                status: .active,
            )
            state.transcriptHistory = request.messages
            state.draftText = ""
            state.sessionList.allRows = [processingSummary]
            state.sessionList.rows = [processingSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
            state.executionPhase = .processing(AiChatRequestLock(
                kind: .submit,
                requestID: requestID,
                runID: runID,
                context: context,
                request: request,
                selectedModelHandle: catalogRows[0].handle,
                selectedModelRow: catalogRows[0],
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: 2,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
                observabilitySummary: AiChatRequestObservabilitySummary(submittedAtMs: firstSubmitMs),
            ))
        }

        XCTAssertEqual(requestSpy.requests.count, 1)
        XCTAssertEqual(requestSpy.requests[0].context.selectedThinking, .effort(.high))
    }

    func testSelectedThinkingChangedDistinguishesProviderDefaultFromNoThinking() async {
        let catalogRows = makeCatalogRows()
        let baseModels = makeThinkingCapableProviderModels()
        let models = [
            AiProviderModel(
                id: baseModels[0].id,
                provider: baseModels[0].provider,
                rawModelID: baseModels[0].rawModelID,
                displayName: baseModels[0].displayName,
                providerDisplayName: baseModels[0].providerDisplayName,
                thinkingCapability: baseModels[0].thinkingCapability,
                supportsThinkingNone: true,
                unavailableReason: baseModels[0].unavailableReason,
            ),
            baseModels[1],
        ]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
        )) {
            AiChatFeature()
        }

        await store.send(.selectedThinkingChanged(AiThinkingSelection.none)) { state in
            state.selectedThinking = AiThinkingSelection.none
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "none")

        await store.send(.selectedThinkingChanged(nil)) { state in
            state.selectedThinking = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "default")
    }

    func testModelSelectorPresentationTogglesWithoutTouchingSelection() async {
        let catalogRows = [makeCatalogRows()[0]]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.isModelSelectorPresented)

        await store.send(.modelSelectorTapped) { state in
            state.isModelSelectorPresented = true
        }

        await store.send(.selectedModelChanged(catalogRows[0].handle))

        await store.send(.modelSelectorDismissed) { state in
            state.isModelSelectorPresented = false
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
        XCTAssertFalse(store.state.isModelSelectorPresented)
    }

    // swiftlint:disable:next function_body_length
    func testProviderConnectionsUpdatedPreservesValidCurrentSelection() async {
        let catalogRows = makeCatalogRows()
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .anthropic,
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
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

    // swiftlint:disable:next function_body_length
    func testProviderConnectionsUpdatedClearsSelectionWhenCurrentModelDisappears() async {
        let catalogRows = makeCatalogRows()
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .anthropic,
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
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

// swiftlint:enable type_body_length

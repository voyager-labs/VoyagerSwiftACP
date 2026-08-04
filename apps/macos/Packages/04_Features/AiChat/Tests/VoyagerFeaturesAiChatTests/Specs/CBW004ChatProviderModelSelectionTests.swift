import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class CBW004ChatProviderModelSelectionTests: XCTestCase {
    // MARK: - CBW-004-show_active_chat_provider_and_model

    /// CBW-004-show_active_chat_provider_and_model: 선택된 provider/model과 thinking 표시를 composer에 노출한다.
    /// 사용자가 현재 선택된 모델과 thinking 상태를 요청 전 확인할 수 있는지 검증합니다.
    /// - 검증 내용: selected model label, generic fallback, thinking unavailable/default label
    /// - 사전 조건: 모델 catalog가 loaded 상태이고 선택 모델이 있거나 없는 상태
    /// - 기대 결과: composer display model이 현재 선택과 capability 상태를 정확히 반영한다.
    func testShowActiveChatProviderAndModelReflectsSelectionAndThinkingCapability() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[1].handle
        let selectedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedHandle,
        )
        let noSelectionState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: nil,
        )
        let supportedThinkingState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: catalogRows[0].handle,
        )

        XCTAssertEqual(AiChatSelectorLabels.modelSelectorLabel(for: selectedState), "Claude Sonnet 4")
        XCTAssertEqual(AiChatSelectorLabels.modelSelectorLabel(for: noSelectionState), "Model")
        XCTAssertEqual(selectedState.chatInputDisplayModel.effortLabel, "Thinking unavailable")
        XCTAssertEqual(supportedThinkingState.chatInputDisplayModel.effortLabel, "default")
    }

    // MARK: - CBW-004-show_available_chat_models

    /// CBW-004-show_available_chat_models: 사용 가능한 모델을 provider section 단위로 표시한다.
    /// 연결 snapshot이 없어도 loaded catalog를 provider별 selector content로 변환하는지 검증합니다.
    /// - 검증 내용: provider별 section title, row title, scrollable content state
    /// - 사전 조건: OpenAI와 Anthropic 모델 catalog가 loaded 상태
    /// - 기대 결과: selector content가 provider별로 그룹화되고 선택 가능한 loaded 상태가 된다.
    func testShowAvailableChatModelsGroupsLoadedModelsByProvider() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            providerConnectionSnapshot: .unknown,
            availableModelsByProvider: [:],
        )

        guard case let .loaded(sections) = state.modelSelectorContentState else {
            return XCTFail("Expected loaded model selector content")
        }

        XCTAssertEqual(sections.map(\.title), [
            aiChatProviderSectionTitle(for: .openai),
            aiChatProviderSectionTitle(for: .anthropic),
        ])
        XCTAssertEqual(sections.first?.rows.map(\.title), ["GPT-4.1 Mini"])
        XCTAssertEqual(sections.last?.rows.map(\.title), ["Claude Sonnet 4"])
        XCTAssertTrue(state.modelSelectorHasPresentableContent)
        XCTAssertFalse(state.modelSelectorIsDisabled)
    }

    // MARK: - CBW-004-select_active_chat_model

    /// CBW-004-select_active_chat_model: 모델 변경은 다음 request에만 적용된다.
    /// processing 중 선택 변경이 locked request를 바꾸지 않고 다음 submit부터 반영되는지 검증합니다.
    /// - 검증 내용: 첫 request lock 모델 보존, in-flight 중 next selection 표시, 두 번째 request 모델 변경
    /// - 사전 조건: OpenAI 모델로 첫 요청이 processing 중인 상태
    /// - 기대 결과: 첫 request는 OpenAI로 유지되고 두 번째 request는 Anthropic으로 생성된다.
    func testSelectActiveChatModelAppliesOnlyToNextRequest() async throws {
        let fixture = makeCBW004SubmitFixture(
            draftText: "Draft",
            selectedHandle: makeCatalogRows()[0].handle,
            selectedThinking: .effort(.medium),
            fixedMs: 1_700_000_000_600,
        )
        let store = fixture.store
        applyCBW004ObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)
        let firstRequest = try XCTUnwrap(fixture.stream.requests.first)
        XCTAssertEqual(firstRequest.context.model, fixture.catalogRows[0].handle)
        XCTAssertEqual(firstRequest.context.selectedThinking, .effort(.medium))

        await store.send(.selectedModelChanged(fixture.catalogRows[1].handle)) { state in
            state.selectedModelHandle = fixture.catalogRows[1].handle
            state.unavailableSelectedModelHandle = nil
        }

        guard case let .processing(lock) = store.state.executionPhase else {
            return XCTFail("Expected request to remain locked while processing")
        }
        XCTAssertEqual(lock.context.model, fixture.catalogRows[0].handle)
        XCTAssertEqual(store.state.selectedModelHandle, fixture.catalogRows[1].handle)

        await store.send(.resetTapped)
        await store.send(.draftTextChanged("Second request")) { state in
            state.draftText = "Second request"
        }
        store.dependencies.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_601))
        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)

        let secondRequest = try XCTUnwrap(fixture.stream.requests.last)
        XCTAssertEqual(fixture.stream.requests.count, 2)
        XCTAssertEqual(secondRequest.context.model, fixture.catalogRows[1].handle)
        XCTAssertEqual(secondRequest.context.selectedModel, fixture.models[1])
    }

    // MARK: - CBW-004-select_chat_model_thinking

    /// CBW-004-select_chat_model_thinking: thinking 선택은 composer label과 다음 request context에 반영된다.
    /// provider default와 명시적 thinking 선택을 구분해 요청 snapshot에 기록하는지 검증합니다.
    /// - 검증 내용: selectedThinkingChanged, display label, submitted request selectedThinking
    /// - 사전 조건: thinking-capable OpenAI 모델이 선택된 상태
    /// - 기대 결과: high thinking 선택이 composer와 provider request context에 동일하게 반영된다.
    func testSelectChatModelThinkingUpdatesDisplayModelAndNextRequestContext() async throws {
        let fixture = makeCBW004SubmitFixture(
            draftText: "Use high thinking",
            selectedHandle: makeCatalogRows()[0].handle,
            selectedThinking: nil,
            fixedMs: 1_700_000_000_700,
        )
        let store = fixture.store
        applyCBW004ObservationFocusedExhaustivity(to: store)

        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "default")
        await store.send(.selectedThinkingChanged(.effort(.high))) { state in
            state.selectedThinking = .effort(.high)
        }
        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "high")

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store)

        let request = try XCTUnwrap(fixture.stream.requests.first)
        XCTAssertEqual(request.context.selectedThinking, .effort(.high))
    }

    /// CBW-004-select_chat_model_thinking: provider default와 no-thinking 선택을 구분한다.
    /// none 선택이 가능한 모델에서 nil과 none이 서로 다른 UI 의미를 유지하는지 검증합니다.
    /// - 검증 내용: `.none` label과 nil default label 전환
    /// - 사전 조건: supportsThinkingNone이 true인 thinking-capable 모델
    /// - 기대 결과: none은 `none`, nil은 provider default label로 표시된다.
    func testSelectChatModelThinkingDistinguishesProviderDefaultFromNoThinking() async {
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

    // MARK: - CBW-004-show_unavailable_chat_model_state

    /// CBW-004-show_unavailable_chat_model_state: model list 비가용 상태를 selector contract로 표시한다.
    /// loading/empty/failed/unsupported provider 상태가 사용자에게 구분되는지 검증합니다.
    /// - 검증 내용: content state, disabled 여부, unsupported provider copy
    /// - 사전 조건: modelListState가 loading, empty, failed, unsupported failure인 상태
    /// - 기대 결과: selector가 각 상태를 명시적 display contract로 노출한다.
    func testShowUnavailableChatModelStateProvidesExplicitSelectorStates() {
        let loadingState = AiChatFeature.State(modelListState: .loading)
        let emptyState = AiChatFeature.State(modelListState: .empty)
        let failedState = AiChatFeature.State(modelListState: .failed(.init(
            message: "Anthropic model list request failed (500).",
        )))
        let unsupportedState = AiChatFeature.State(modelListState: .failed(.init(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider,
        )))

        XCTAssertEqual(loadingState.modelSelectorContentState, .loading(.init(
            title: "Loading models",
            detail: "Fetching available models from connected providers.",
        )))
        XCTAssertEqual(emptyState.modelSelectorContentState, .empty(.init(
            title: "No models available",
            detail: "No selectable models are available for the current provider setup.",
        )))
        XCTAssertEqual(failedState.modelSelectorContentState, .failed(.init(
            title: "Models unavailable",
            detail: "Anthropic model list request failed (500).",
        )))
        XCTAssertEqual(unsupportedState.modelSelectorContentState, .unsupported(.init(
            title: "Provider unsupported",
            detail: "ChatGPT Codex model listing is unavailable.",
        )))
        XCTAssertFalse(emptyState.modelSelectorIsDisabled)
        XCTAssertFalse(unsupportedState.modelSelectorIsDisabled)
    }

    /// CBW-004-show_unavailable_chat_model_state: 현재 선택 모델이 catalog에서 사라지면 제출을 막는다.
    /// provider/model refresh 이후 unavailable selection을 보존해 사용자에게 다시 선택을 요구하는지 검증합니다.
    /// - 검증 내용: selected model clear, unavailable handle 보존, composer label, canSubmit false
    /// - 사전 조건: OpenAI 모델 선택 중 Anthropic 모델만 다시 loaded 되는 상태
    /// - 기대 결과: 선택은 해제되고 기존 handle은 unavailableSelectedModelHandle로 남는다.
    func testShowUnavailableChatModelStateClearsMissingSelectionAfterRefresh() async {
        let catalogRows = makeCatalogRows()
        let remainingModel = makeProviderModels()[1]
        let requestID = makeUUID("00000000-0000-0000-0000-000000000020")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[0].handle,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic],
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
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
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: [remainingModel]]
            state.lastExecutionFailure = nil
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, catalogRows[0].handle)
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertFalse(store.state.canSubmit)
    }

    // MARK: - CBW-004-show_available_chat_models

    /// CBW-004-show_available_chat_models: provider 연결 변경이 stale model batch를 취소하고 최신 batch만 반영한다.
    /// provider 연결 변경이 stale model batch를 취소하고 최신 batch만 반영한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: in-flight batch cancellation, stale response ignore, latest provider rows only
    /// - 사전 조건: provider connection update가 연속으로 들어오고 첫 번째 batch가 아직 완료되지 않았다.
    /// - 기대 결과: 취소된 batch 결과는 무시되고 최신 provider 기준 model catalog만 유지된다.
    func testProviderConnectionUpdatesCancelInFlightBatchAndIgnoreStaleResponse() async {
        actor LoadDriver {
            var startedProviders: [AiProvider] = []
            var cancellationCount = 0

            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                startedProviders.append(provider)

                if startedProviders.count == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        return makeProviderModels()
                    } catch is CancellationError {
                        cancellationCount += 1
                        throw CancellationError()
                    }
                }

                return [makeProviderModels()[1]]
            }

            func snapshot() -> (startedProviders: [AiProvider], cancellationCount: Int) {
                (startedProviders, cancellationCount)
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let openAIFile = makeConnectionsFile(
            providers: [makeProviderRecord(provider: .openai, credential: openAICredential)],
            lastUsedProviderId: .openai,
        )
        let anthropicFile = makeConnectionsFile(
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
            updatedAtMs: 2,
            lastUsedProviderId: .anthropic,
        )
        let driver = LoadDriver()
        let firstRequestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let secondRequestID = makeUUID("00000000-0000-0000-0000-000000000001")
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
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(openAIFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = firstRequestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai]
            state.modelListPendingProviders = [.openai]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: firstRequestID,
            provider: .openai,
            credential: openAICredential,
        ))

        await store.send(.providerConnectionsUpdated(anthropicFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = secondRequestID
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = [.anthropic]
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: secondRequestID,
            provider: .anthropic,
            credential: anthropicCredential,
        ))

        await store.receive(.modelListLoaded(
            requestID: secondRequestID,
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

        await store.send(.modelListLoaded(
            requestID: firstRequestID,
            provider: .openai,
            models: makeProviderModels(),
        ))

        try? await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = await driver.snapshot()
        XCTAssertEqual(snapshot.startedProviders, [.openai, .anthropic])
        XCTAssertEqual(snapshot.cancellationCount, 1)
        XCTAssertEqual(store.state.modelListState, .loaded([remainingModel]))
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, catalogRows[0].handle)
    }

    /// CBW-004-show_available_chat_models: 여러 connected provider의 model list를 하나의 selector catalog로 병합한다.
    /// 여러 connected provider의 model list를 하나의 selector catalog로 병합한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: provider order 유지, merged catalog rows, availableModelsByProvider snapshot
    /// - 사전 조건: OpenAI와 Anthropic이 모두 연결되어 있고 각각 모델을 반환한다.
    /// - 기대 결과: selector content가 provider별 row를 모두 포함한 loaded state로 채워진다.
    func testProviderConnectionsUpdatedMergesModelsFromMultipleConnectedProviders() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .anthropic:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    return [makeProviderModels()[1]]
                case .chatgptCodex:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .anthropic, credential: anthropicCredential),
            ],
            lastUsedProviderId: .openai,
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let anthropicModels = [makeProviderModels()[1]]
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .anthropic]
            state.modelListPendingProviders = [.openai, .anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential,
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .anthropic,
            credential: anthropicCredential,
        )) { state in
            state.modelListProvider = .anthropic
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels,
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: anthropicModels,
        )) { state in
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [.openai: openAIModels, .anthropic: anthropicModels]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.modelCatalogState.sections.map(\.title), [
            aiChatProviderSectionTitle(for: .openai),
            aiChatProviderSectionTitle(for: .anthropic),
        ])
        XCTAssertEqual(store.state.modelCatalogState.sections.first?.rows.map(\.title), ["GPT-4.1 Mini"])
        XCTAssertNil(store.state.modelCatalogState.sections.first?.rows.first?.providerBadge)
        XCTAssertEqual(store.state.modelCatalogState.sections.last?.rows.first?.providerBadge, "Reasoning-first chat")
    }

    /// CBW-004-show_available_chat_models: 일부 provider 로드 실패가 다른 provider의 성공 catalog를 지우지 않는다.
    /// 일부 provider 로드 실패가 다른 provider의 성공 catalog를 지우지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: partial failure handling, successful provider preservation, failure surface
    /// - 사전 조건: 둘 이상의 provider 중 하나만 model list 로드에 실패한다.
    /// - 기대 결과: 성공한 provider 모델은 유지되고 실패 정보만 추가로 반영된다.
    func testModelListPartialFailurePreservesSuccessfulModelsFromAnotherProvider() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .anthropic:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    throw AiProviderModelListError.invalidResponse(.anthropic)
                case .chatgptCodex:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .anthropic, credential: anthropicCredential),
            ],
            lastUsedProviderId: .openai,
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let anthropicFailure = AiModelListFailure(message: "Anthropic returned an invalid model list response.")
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .anthropic]
            state.modelListPendingProviders = [.openai, .anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential,
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .anthropic,
            credential: anthropicCredential,
        )) { state in
            state.modelListProvider = .anthropic
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels,
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .anthropic,
            failure: anthropicFailure,
        )) { state in
            state.catalogRows = [catalogRows[0]]
            state.modelListState = .loaded(openAIModels)
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.anthropic: anthropicFailure]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [.openai: openAIModels, .anthropic: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "GPT-4.1 Mini")
        XCTAssertEqual(store.state.availableModels, openAIModels)
        XCTAssertEqual(store.state.modelListFailedProviders, [.anthropic: anthropicFailure])
    }

    /// CBW-004-show_available_chat_models: Codex 로드 실패가 이미 성공한 OpenAI catalog를 유지한다.
    /// Codex 로드 실패가 이미 성공한 OpenAI catalog를 유지한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: Codex failure isolation, OpenAI rows preservation, provider availability state
    /// - 사전 조건: OpenAI는 성공하고 Codex는 unsupported failure를 반환한다.
    /// - 기대 결과: selector는 OpenAI 모델을 계속 노출하고 Codex 실패만 분리해서 다룬다.
    func testModelListCodexFailurePreservesSuccessfulOpenAIModels() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .chatgptCodex:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    throw AiProviderModelListError.unsupportedProvider(.chatgptCodex)
                case .anthropic:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ],
            lastUsedProviderId: .openai,
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let codexFailure = AiModelListFailure(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider,
        )
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .chatgptCodex]
            state.modelListPendingProviders = [.openai, .chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential,
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential,
        )) { state in
            state.modelListProvider = .chatgptCodex
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels,
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .chatgptCodex,
            failure: codexFailure,
        )) { state in
            state.catalogRows = [catalogRows[0]]
            state.modelListState = .loaded(openAIModels)
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.chatgptCodex: codexFailure]
            state.providerConnectionSnapshot = .known([.openai, .chatgptCodex])
            state.availableModelsByProvider = [.openai: openAIModels, .chatgptCodex: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.availableModels, openAIModels)
        XCTAssertEqual(store.state.modelListFailedProviders, [.chatgptCodex: codexFailure])
    }

    /// CBW-004-show_available_chat_models: Codex-only 연결에서도 selectable model과 thinking metadata를 로드한다.
    /// Codex-only 연결에서도 selectable model과 thinking metadata를 로드한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: Codex catalog row, provider display metadata, thinking capability hydration
    /// - 사전 조건: 연결된 provider가 ChatGPT Codex 하나뿐이다.
    /// - 기대 결과: Codex model row가 selector에 로드되고 thinking capability metadata도 보존된다.
    func testModelListCodexOnlySuccessLoadsCodexModelsAndThinkingMetadata() async {
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            providers: [
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ],
            lastUsedProviderId: .chatgptCodex,
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let codexModel = AiProviderModel(
            id: AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5.5"),
            provider: .chatgptCodex,
            rawModelID: "gpt-5.5",
            displayName: "GPT-5.5",
            providerDisplayName: ProviderDescriptor.descriptor(for: .chatgptCodex)?.displayName ?? "ChatGPT Codex",
            thinkingCapability: .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium),
            unavailableReason: nil,
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            selectedModelHandle: codexModel.id,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                XCTAssertEqual(provider, .chatgptCodex)
                XCTAssertEqual(credential, codexCredential)
                return [codexModel]
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = [.chatgptCodex]
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential,
        ))
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .chatgptCodex,
            models: [codexModel],
        )) { state in
            state.catalogRows = [
                AiModelCatalogRow(
                    handle: codexModel.id,
                    displayName: codexModel.displayName,
                    authMethod: .oauth,
                    subtitle: nil,
                    sortOrder: 0,
                    isDefault: false,
                    isRecommended: false,
                ),
            ]
            state.modelListState = .loaded([codexModel])
            state.selectedModelHandle = codexModel.id
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [.chatgptCodex: [codexModel]]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "GPT-5.5")
        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "default")
        XCTAssertEqual(
            store.state.resolvedSelectedModel?.thinkingCapability,
            .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium),
        )
    }

    // MARK: - CBW-004-select_active_chat_model

    /// CBW-004-select_active_chat_model: Codex model 선택이 CLI execution path에서도 submit 가능 상태를 만든다.
    /// Codex model 선택이 CLI execution path에서도 submit 가능 상태를 만든다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: canSubmit, requestStatusText, selected Codex model state
    /// - 사전 조건: active chat에 Codex model row 하나가 선택되어 있다.
    /// - 기대 결과: Codex 선택 상태가 일반 provider 선택과 동일하게 submit 가능 contract를 충족한다.
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

    /// CBW-004-select_active_chat_model: 같은 model handle을 유지하면서 최신 catalog display name으로 갱신한다.
    /// 같은 model handle을 유지하면서 최신 catalog display name으로 갱신한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: handle preservation, refreshed displayName, stale row metadata carry-over
    /// - 사전 조건: 기존 catalog row와 같은 handle을 가진 새 provider model metadata가 도착한다.
    /// - 기대 결과: 선택 handle은 유지되고 사용자에게 보이는 display name은 최신 값으로 갱신된다.
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

    /// CBW-004-select_active_chat_model: refresh 이후에도 현재 model이 catalog에 남아 있으면 선택을 유지한다.
    /// refresh 이후에도 현재 model이 catalog에 남아 있으면 선택을 유지한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: selectedModelHandle preservation, loaded catalog, unavailable handle clear
    /// - 사전 조건: loading 중인 model list가 기존 선택 handle을 포함한 결과로 돌아온다.
    /// - 기대 결과: 현재 선택은 유지되고 unavailable fallback으로 내려가지 않는다.
    func testModelListLoadedKeepsCurrentSelectionWhenStillPresent() async {
        let models = makeProviderModels()
        let catalogRows = makeCatalogRows()
        let requestID = makeUUID("00000000-0000-0000-0000-000000000010")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[1].handle,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic],
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models,
        )) { state in
            state.modelListState = .loaded(models)
            state.selectedModelHandle = catalogRows[1].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: models]
            state.lastExecutionFailure = nil
        }
    }

    /// CBW-004-select_active_chat_model: provider 연결이 바뀌어도 현재 선택 model이 유효하면 계속 선택 상태로 유지한다.
    /// provider 연결이 바뀌어도 현재 선택 model이 유효하면 계속 선택 상태로 유지한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: selection preservation across provider refresh, catalog reload, availableModelsByProvider
    /// - 사전 조건: provider connection update 뒤 새 catalog가 기존 selected handle을 포함한다.
    /// - 기대 결과: selected model handle은 그대로 유지되고 submit 가능 상태도 보존된다.
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

    /// CBW-004-select_active_chat_model: setup은 누락된 model selection을 임의 기본값으로 자동 보정하지 않는다.
    /// setup은 누락된 model selection을 임의 기본값으로 자동 보정하지 않는다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: no implicit auto-selection, empty selected model display, canSubmit false
    /// - 사전 조건: setup state에 catalog rows는 있지만 selectedModelHandle은 비어 있다.
    /// - 기대 결과: selected model은 nil로 남고 사용자가 명시적으로 선택하기 전까지 submit할 수 없다.
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

    /// CBW-004-select_active_chat_model: restore된 model handle이 현재 catalog에 있으면 최신 row metadata로 정규화한다.
    /// restore된 model handle이 현재 catalog에 있으면 최신 row metadata로 정규화한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: restored selectedModelRow normalization, latest display metadata, restore outcome snapshot
    /// - 사전 조건: persisted snapshot의 selectedModelRow metadata가 낡았지만 handle은 현재 catalog에 존재한다.
    /// - 기대 결과: 복원 후 선택 handle은 유지되고 restore outcome snapshot도 최신 catalog row를 참조한다.
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
            isRecommended: false,
        )
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: catalogRows[1].handle.provider,
            model: catalogRows[1].handle,
            selectedModelRow: staleSelectedRow,
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
                saveSession: { snapshot in snapshot },
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
            selectedModelHandle: catalogRows[0].handle,
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
            updatedAtMs: 0,
        )

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: normalizedSnapshot),
            restoreFailure: nil,
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

    // MARK: - CBW-004-select_chat_model_thinking

    /// CBW-004-select_chat_model_thinking: 같은 model selection은 유지하면서 호환되지 않는 thinking 값만 정리한다.
    /// 같은 model selection은 유지하면서 호환되지 않는 thinking 값만 정리한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: selection preservation, incompatible thinking clear, loaded model capabilities
    /// - 사전 조건: 선택 모델은 유지되지만 새 capability가 기존 thinking 값을 더 이상 지원하지 않는다.
    /// - 기대 결과: selected model handle은 유지되고 selectedThinking만 nil로 정리된다.
    func testModelListLoadedKeepsSelectionButClearsIncompatibleThinking() async {
        let models = makeThinkingCapableProviderModels()
        let catalogRows = makeCatalogRows()
        let requestID = makeUUID("00000000-0000-0000-0000-000000000011")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.high),
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic],
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models,
        )) { state in
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
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: models]
            state.lastExecutionFailure = nil
        }
    }

    /// CBW-004-select_chat_model_thinking: restore 직후 concrete model capability가 로드되면 incompatible thinking을 정리한다.
    /// restore 직후 concrete model capability가 로드되면 incompatible thinking을 정리한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: restored thinking cleanup after provider refresh, concrete capability load, selection preservation
    /// - 사전 조건: restored snapshot이 높은 thinking 값을 갖고 있고 이후 실제 provider model capability가 로드된다.
    /// - 기대 결과: 복원된 model selection은 유지되며 호환되지 않는 thinking 값만 제거된다.
    func testRestoreClearsIncompatibleThinkingWhenConcreteModelCapabilitiesLoad() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("12121212-1212-1212-1212-121212121212"))
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)],
            lastUsedProviderId: .anthropic,
        )
        let restoredSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: .anthropic,
            model: catalogRows[1].handle,
            selectedModelRow: catalogRows[1],
            selectedThinking: .effort(.high),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            updatedAtMs: 0,
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        let models = makeThinkingCapableProviderModels()
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { snapshot in snapshot },
                deleteSession: { _ in },
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
            lastExecutionFailure: nil,
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

        await store.receive(AiChatAction.restoreOutcome(
            requestedSessionID: targetSessionID,
            AiChatSessionRestoreResult.restored(snapshot: restoredSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
            state.selectedModelHandle = restoredSnapshot.model
            state.selectedThinking = restoredSnapshot.selectedThinking
            state.restoreOutcome = AiChatSessionRestoreResult.restored(snapshot: restoredSnapshot)
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
            credential: anthropicCredential,
        ))
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models,
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

    // MARK: - CBW-004-show_unavailable_chat_model_state

    /// CBW-004-show_unavailable_chat_model_state: Codex-only 로드 실패는 unsupported provider 상태를 명시적으로 노출한다.
    /// Codex-only 로드 실패는 unsupported provider 상태를 명시적으로 노출한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: failed selector state, unsupported provider reason, user-facing copy
    /// - 사전 조건: 연결된 provider가 Codex 하나뿐이고 model listing이 unsupported failure를 반환한다.
    /// - 기대 결과: selector는 disabled copy 대신 unsupported provider 상태와 실패 메시지를 노출한다.
    func testModelListCodexOnlyFailureTransitionsToFailedStateAndExposesUnsupportedProvider() async {
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            providers: [
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ],
            lastUsedProviderId: .chatgptCodex,
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let codexFailure = AiModelListFailure(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider,
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, _ in
                XCTAssertEqual(provider, .chatgptCodex)
                throw AiProviderModelListError.unsupportedProvider(.chatgptCodex)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = [.chatgptCodex]
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential,
        ))
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .chatgptCodex,
            failure: codexFailure,
        )) { state in
            state.modelListState = .failed(codexFailure)
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.chatgptCodex: codexFailure]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, codexFailure.message)
        XCTAssertEqual(store.state.modelListFailedProviders, [.chatgptCodex: codexFailure])
    }

    /// CBW-004-show_unavailable_chat_model_state: provider refresh 뒤 현재 선택 model이 사라지면 unavailable selection으로 전환한다.
    /// provider refresh 뒤 현재 선택 model이 사라지면 unavailable selection으로 전환한다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: selected handle clear, unavailableSelectedModelHandle preservation, canSubmit false
    /// - 사전 조건: 새 catalog가 기존 selected handle을 포함하지 않는다.
    /// - 기대 결과: 사용자 선택은 해제되고 이전 handle은 unavailableSelectedModelHandle로 보존된다.
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

    /// CBW-004-show_unavailable_chat_model_state: restore된 model이 현재 catalog에 없으면 unavailable selection으로 남긴다.
    /// restore된 model이 현재 catalog에 없으면 unavailable selection으로 남긴다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: restored missing model handling, unavailableSelectedModelHandle, submit block
    /// - 사전 조건: persisted snapshot의 model handle이 현재 catalog 어디에도 없다.
    /// - 기대 결과: 복원은 transcript를 유지하되 selected model은 비우고 다시 선택하도록 요구한다.
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
            updatedAtMs: 0,
        )
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { _ in restoredSnapshot })
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { id in try await persistence.loadSession(id) },
                saveSession: { snapshot in snapshot },
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
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = restoredSnapshot.model
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        await store.receive(AiChatAction.restoreOutcome(
            requestedSessionID: targetSessionID,
            AiChatSessionRestoreResult.restored(snapshot: restoredSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = restoredSnapshot.transcriptHistory
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = restoredSnapshot.model
            state.restoreOutcome = AiChatSessionRestoreResult.restored(snapshot: restoredSnapshot)
            state.restoreFailure = nil
        }

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, restoredSnapshot.model)
        XCTAssertNil(store.state.modelCatalogState.selectedModel)
        XCTAssertFalse(store.state.canSubmit)
    }

    /// CBW-004-show_unavailable_chat_model_state: model list load 실패는 selector failed state로 전환된다.
    /// model list load 실패는 selector failed state로 전환된다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: failure state transition, request bookkeeping reset, failed provider snapshot
    /// - 사전 조건: loading 중인 provider request가 실패를 반환한다.
    /// - 기대 결과: selector 상태는 failed로 바뀌고 pending request bookkeeping은 정리된다.
    func testModelListLoadFailedTransitionsToFailedState() async {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000030")
        let failure = AiModelListFailure(message: "Anthropic model list request failed (500).")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            modelListState: .loading,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic],
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoadFailed(
            requestID: requestID,
            provider: .anthropic,
            failure: failure,
        )) { state in
            state.modelListState = .failed(failure)
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.anthropic: failure]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }
    }

    /// CBW-004-show_unavailable_chat_model_state: connected provider가 없으면 unconnected/empty selector 상태로 되돌린다.
    /// connected provider가 없으면 unconnected/empty selector 상태로 되돌린다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: catalog clear, selection clear, provider snapshot empty, unavailable handle preservation
    /// - 사전 조건: 기존 selection이 있는 상태에서 모든 provider connection이 끊긴다.
    /// - 기대 결과: catalog와 selection은 정리되고 selector는 연결 없음에 해당하는 상태를 노출한다.
    func testProviderConnectionsUpdatedWithNoConnectedProvidersRestoresUnconnectedState() async {
        let selectedHandle = makeCatalogRows()[0].handle
        let file = makeConnectionsFile(providers: [
            makeProviderRecord(provider: .openai, state: .disconnected),
        ])
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedHandle,
            selectedThinking: .effort(.medium),
        )) {
            AiChatFeature()
        }

        await store.send(.providerConnectionsUpdated(file)) { state in
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = selectedHandle
            state.modelListProvider = nil
            state.providerConnectionSnapshot = .known([])
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings",
        )))
        if case let .unconnected(connection, _) = store.state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
        } else {
            XCTFail("Expected unconnected surface state")
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    /// CBW-004-show_unavailable_chat_model_state: provider가 빈 model 결과를 반환하면 selector empty state로 전환된다.
    /// provider가 빈 model 결과를 반환하면 selector empty state로 전환된다. 경로의 회귀 contract를 유지하는지 검증합니다.
    /// - 검증 내용: empty model result handling, selection clear, canSubmit false
    /// - 사전 조건: loading 중인 provider request가 빈 model 배열로 완료된다.
    /// - 기대 결과: catalog는 비워지고 사용자는 다시 연결 또는 다른 provider 선택을 해야 한다.
    func testModelListLoadedWithEmptyModelsTransitionsToEmptyState() async {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000040")
        let selectedHandle = makeCatalogRows()[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loading,
            selectedModelHandle: selectedHandle,
            modelListRequestID: requestID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: [],
        )) { state in
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = selectedHandle
            state.modelListRequestID = nil
            state.modelListProvider = .openai
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.openai: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "No models available")
    }

    /// 현재 loaded model 목록에 없는 선택 모델로 regenerate가 차단되는지 검증
    // MARK: - CBW-004-show_unavailable_chat_model_state

    /// CBW-004-show_unavailable_chat_model_state: Regenerate Is Blocked When Selected Model Is Not In Current Loaded
    /// List
    /// CBW-004 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testRegenerateIsBlockedWhenSelectedModelIsNotInCurrentLoadedList() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = [makeThinkingCapableProviderModels()[1]]
        let missingHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111115"))

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Old answer"),
            ],
            draftText: "",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: missingHandle,
            selectedThinking: .effort(.medium),
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
        }
        // store.exhaustivity = .off: regenerate guard가 no-op인지와 request 미생성만 확인하면 충분합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped)

        XCTAssertTrue(stream.requests.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
    }

    // MARK: - CBW-004-show_unavailable_chat_model_state

    /// CBW-004-show_unavailable_chat_model_state: unavailable non-nil 모델 action은 현재 선택을 바꾸지 않는다.
    /// stale UI가 unavailable B를 보내도 유효한 A와 모든 draft bookkeeping을 보존하는지 검증합니다.
    /// - 검증 내용: 전체 state/effect no-op, transient marker, Thinking, recovery/failure bookkeeping, active locks
    /// - 사전 조건: available A가 선택되고 같은 catalog의 B는 unavailable인 processing 상태
    /// - 기대 결과: unavailable B action 전후 State가 완전히 같고 effect가 생성되지 않는다.
    func testSelectedModelChangedWithUnavailableNonNilHandleIsCompleteNoOp() async {
        let models = makeThinkingCapableProviderModels()
        let unavailableModel = makeCBW004UnavailableModel(models[1])
        let initialState = makeCBW004SelectionBookkeepingState(models: [models[0], unavailableModel])
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(unavailableModel.id))

        XCTAssertEqual(store.state, initialState)
        await store.finish()
    }

    /// CBW-004-show_unavailable_chat_model_state: absent non-nil 모델 action은 현재 선택을 바꾸지 않는다.
    /// catalog에 없는 B가 전달되어도 explicit deselection으로 해석되지 않는지 검증합니다.
    /// - 검증 내용: 전체 state/effect no-op, transient marker, Thinking, recovery/failure bookkeeping, active locks
    /// - 사전 조건: available A가 선택되고 요청된 B handle은 loaded catalog에 없는 processing 상태
    /// - 기대 결과: absent B action 전후 State가 완전히 같고 effect가 생성되지 않는다.
    func testSelectedModelChangedWithAbsentNonNilHandleIsCompleteNoOp() async {
        let initialState = makeCBW004SelectionBookkeepingState(models: makeThinkingCapableProviderModels())
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(makeUnresolvableModelHandle()))

        XCTAssertEqual(store.state, initialState)
        await store.finish()
    }

    /// CBW-004-select_active_chat_model: explicit nil은 draft 선택만 명시적으로 해제한다.
    /// stale non-nil no-op과 달리 nil action이 선택/Thinking/recovery presentation을 지우는지 검증합니다.
    /// - 검증 내용: draft selection clear, mutation tracking, active/background lock preservation
    /// - 사전 조건: available A와 Thinking, recovery/failure bookkeeping, active locks가 존재한다.
    /// - 기대 결과: draft selection bookkeeping은 정리되고 request-scoped lock은 그대로 유지된다.
    func testSelectedModelChangedWithNilExplicitlyDeselectsAndPreservesLocks() async {
        let initialState = makeCBW004SelectionBookkeepingState(models: makeThinkingCapableProviderModels())
        let lockedModelHandle = initialState.lockedModelHandle
        let executionPhase = initialState.executionPhase
        let backgroundExecutionPhases = initialState.backgroundExecutionPhases
        var expectedState = initialState
        expectedState.newChatPreparationMutationTracker.value &+= 1
        expectedState.preparedTransientSessionID = nil
        expectedState.selectedModelHandle = nil
        expectedState.selectedThinking = nil
        expectedState.unavailableSelectedModelHandle = nil
        expectedState.lastExecutionFailure = nil
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(nil)) { state in
            state = expectedState
        }

        XCTAssertEqual(store.state.lockedModelHandle, lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, executionPhase)
        XCTAssertEqual(store.state.backgroundExecutionPhases, backgroundExecutionPhases)
    }

    /// CBW-004-select_active_chat_model: available B action은 B를 선택하고 Thinking을 정규화한다.
    /// stale non-nil guard가 정상 선택 경로를 막지 않고 기존 capability policy를 유지하는지 검증합니다.
    /// - 검증 내용: selected model 변경, incompatible Thinking normalization, active/background lock preservation
    /// - 사전 조건: available A와 high Thinking이 선택되고 available B는 high를 지원하지 않는다.
    /// - 기대 결과: draft는 B/provider default로 바뀌고 request-scoped lock은 그대로 유지된다.
    func testSelectedModelChangedWithAvailableHandleSelectsAndNormalizesThinking() async {
        let models = makeThinkingCapableProviderModels()
        let initialState = makeCBW004SelectionBookkeepingState(models: models)
        let lockedModelHandle = initialState.lockedModelHandle
        let executionPhase = initialState.executionPhase
        let backgroundExecutionPhases = initialState.backgroundExecutionPhases
        var expectedState = initialState
        expectedState.newChatPreparationMutationTracker.value &+= 1
        expectedState.preparedTransientSessionID = nil
        expectedState.selectedModelHandle = models[1].id
        expectedState.selectedThinking = nil
        expectedState.unavailableSelectedModelHandle = nil
        expectedState.lastExecutionFailure = nil
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(models[1].id)) { state in
            state = expectedState
        }

        XCTAssertEqual(store.state.lockedModelHandle, lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, executionPhase)
        XCTAssertEqual(store.state.backgroundExecutionPhases, backgroundExecutionPhases)
    }

    /// CBW-004-select_chat_model_thinking: capability별 Thinking 선택을 중립 정책으로 정규화한다.
    /// Chat과 Collection Search가 provider와 무관하게 같은 호환성 규칙을 사용하는지 검증합니다.
    /// - 검증 내용: provider default, none, effort, token budget, unknown capability 정규화
    /// - 사전 조건: 각 capability와 supportsNone 값을 독립 입력으로 제공한다.
    /// - 기대 결과: 호환 값은 유지되고 비호환 값만 provider default인 nil로 정리된다.
    func testThinkingSelectionPolicyNormalizesCapabilityMatrix() {
        let effort = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: .low)
        let tokenBudget = AiModelThinkingCapability.tokenBudget(min: 128, max: 1024, defaultValue: 512)
        let unknown = AiModelThinkingCapability.unknown(reason: .init(message: "Metadata pending"))
        let unsupported = AiModelThinkingCapability.unsupported(reason: .init(message: "Unavailable"))

        XCTAssertNil(AiThinkingSelectionPolicy.normalize(nil, capability: effort, supportsNone: true))
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(AiThinkingSelection.none, capability: effort, supportsNone: true),
            AiThinkingSelection.none,
        )
        XCTAssertNil(AiThinkingSelectionPolicy.normalize(
            AiThinkingSelection.none,
            capability: effort,
            supportsNone: false,
        ))
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(.effort(.high), capability: effort, supportsNone: false),
            .effort(.high),
        )
        XCTAssertNil(AiThinkingSelectionPolicy.normalize(.effort(.medium), capability: effort, supportsNone: false))
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(.tokenBudget(512), capability: tokenBudget, supportsNone: false),
            .tokenBudget(512),
        )
        XCTAssertNil(
            AiThinkingSelectionPolicy.normalize(.tokenBudget(64), capability: tokenBudget, supportsNone: false),
        )
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(.effort(.xhigh), capability: unknown, supportsNone: false),
            .effort(.xhigh),
        )
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(.tokenBudget(777), capability: unknown, supportsNone: false),
            .tokenBudget(777),
        )
        XCTAssertEqual(
            AiThinkingSelectionPolicy.normalize(AiThinkingSelection.none, capability: unknown, supportsNone: true),
            AiThinkingSelection.none,
        )
        XCTAssertNil(AiThinkingSelectionPolicy.normalize(
            AiThinkingSelection.none,
            capability: unsupported,
            supportsNone: true,
        ))
    }

    /// CBW-004-select_chat_model_thinking: effort와 adaptive 옵션의 catalog 순서와 라벨을 보존한다.
    /// selector가 중립 옵션 표현을 사용해 기존 사용자 노출 순서를 그대로 만드는지 검증합니다.
    /// - 검증 내용: provider default, none, effort/adaptive ordering, exact visible labels
    /// - 사전 조건: supportsNone과 순서가 지정된 effort/adaptive capability
    /// - 기대 결과: 기본 옵션 뒤에 capability catalog 순서대로 정확한 라벨이 이어진다.
    func testThinkingSelectionPolicyPreservesEffortAndAdaptiveOptionOrderingAndLabels() {
        let effortOptions = AiThinkingSelectionPolicy.options(
            capability: .effort(values: [.low, .xhigh], defaultValue: .low),
            supportsNone: true,
        )
        XCTAssertEqual(effortOptions.map(\.selection), [nil, AiThinkingSelection.none, .effort(.low), .effort(.xhigh)])
        XCTAssertEqual(effortOptions.map(\.title), ["Provider default", "none", "low", "x-high"])

        let adaptiveOptions = AiThinkingSelectionPolicy.options(
            capability: .adaptive(effortValues: [.high, .minimal, .medium], defaultValue: .medium),
            supportsNone: false,
        )
        XCTAssertEqual(
            adaptiveOptions.map(\.selection),
            [nil, .effort(.high), .effort(.minimal), .effort(.medium)],
        )
        XCTAssertEqual(adaptiveOptions.map(\.title), ["Provider default", "high", "minimal", "medium"])
    }

    /// CBW-004-select_chat_model_thinking: token budget 옵션과 unknown capability 출력을 정규화한다.
    /// token selector의 대표 경계값과 metadata 미확정 상태의 빈 옵션 계약을 검증합니다.
    /// - 검증 내용: min/distinct default/max ordering, token labels, duplicate 제거, unknown options
    /// - 사전 조건: token budget 범위와 distinct 또는 min과 같은 default 값
    /// - 기대 결과: 중복 없는 경계 옵션이 순서대로 생성되고 unknown capability는 옵션을 만들지 않는다.
    func testThinkingSelectionPolicyBuildsTokenBudgetOptionsAndNoUnknownOptions() {
        let options = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 128, max: 1024, defaultValue: 512),
            supportsNone: false,
        )
        XCTAssertEqual(options.map(\.selection), [nil, .tokenBudget(128), .tokenBudget(512), .tokenBudget(1024)])
        XCTAssertEqual(options.map(\.title), ["Provider default", "128 tokens", "512 tokens", "1024 tokens"])

        let duplicateMinimumDefaultOptions = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 128, max: 1024, defaultValue: 128),
            supportsNone: false,
        )
        XCTAssertEqual(duplicateMinimumDefaultOptions.map(\.selection), [nil, .tokenBudget(128), .tokenBudget(1024)])

        let duplicateMaximumDefaultOptions = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 128, max: 1024, defaultValue: 1024),
            supportsNone: false,
        )
        XCTAssertEqual(duplicateMaximumDefaultOptions.map(\.selection), [nil, .tokenBudget(128), .tokenBudget(1024)])

        let singleValueOptions = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 512, max: 512, defaultValue: 512),
            supportsNone: false,
        )
        XCTAssertEqual(singleValueOptions.map(\.selection), [nil, .tokenBudget(512)])

        let belowMinimumDefaultOptions = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 128, max: 1024, defaultValue: 64),
            supportsNone: true,
        )
        XCTAssertEqual(
            belowMinimumDefaultOptions.map(\.selection),
            [nil, AiThinkingSelection.none, .tokenBudget(128), .tokenBudget(1024)],
        )

        let aboveMaximumDefaultOptions = AiThinkingSelectionPolicy.options(
            capability: .tokenBudget(min: 128, max: 1024, defaultValue: 2048),
            supportsNone: false,
        )
        XCTAssertEqual(aboveMaximumDefaultOptions.map(\.selection), [nil, .tokenBudget(128), .tokenBudget(1024)])
        XCTAssertTrue(AiThinkingSelectionPolicy.options(
            capability: .unknown(reason: .init(message: "Metadata pending")),
            supportsNone: true,
        ).isEmpty)
        XCTAssertEqual(AiThinkingSelectionPolicy.defaultLabel(for: .effort(values: [], defaultValue: nil)), "default")
        XCTAssertEqual(
            AiThinkingSelectionPolicy.defaultLabel(for: .unknown(reason: .init(message: "Metadata pending"))),
            "Thinking unavailable",
        )
    }

    // MARK: - CBW-004-show_available_chat_models

    /// CBW-004-show_available_chat_models: 기존 7-인자 row initializer의 source compatibility를 보존한다.
    /// VOY-678 이전 public 호출자가 새 menu metadata를 전달하지 않아도 기존 동작으로 초기화되는지 검증합니다.
    /// - 검증 내용: public initializer signature, enabled default, disabled reason, accessibility defaults
    /// - 사전 조건: selected와 not-selected row를 기존 7개 인자로만 생성합니다.
    /// - 기대 결과: 두 row 모두 enabled이고 label 기반 접근성 값이 selection 상태를 반영합니다.
    func testModelCatalogRowLegacyInitializerPreservesConservativeMenuDefaults() {
        let handle = AiModelHandle(provider: .openai, rawValue: "legacy-model")
        let label = AiChatModelLabel(title: "Legacy model", subtitle: "OpenAI")
        let selectedRow = AiChatModelCatalogRowDisplayModel(
            handle: handle,
            label: label,
            providerBadge: "OpenAI",
            isSelected: true,
            isLocked: false,
            isDefault: true,
            isRecommended: false,
        )
        let notSelectedRow = AiChatModelCatalogRowDisplayModel(
            handle: handle,
            label: label,
            providerBadge: "OpenAI",
            isSelected: false,
            isLocked: false,
            isDefault: true,
            isRecommended: false,
        )

        XCTAssertTrue(selectedRow.isEnabled)
        XCTAssertNil(selectedRow.disabledReason)
        XCTAssertEqual(selectedRow.accessibilityLabel, label.title)
        XCTAssertEqual(selectedRow.accessibilityValue, "Selected")
        XCTAssertTrue(notSelectedRow.isEnabled)
        XCTAssertNil(notSelectedRow.disabledReason)
        XCTAssertEqual(notSelectedRow.accessibilityLabel, label.title)
        XCTAssertEqual(notSelectedRow.accessibilityValue, "Not selected")
    }

    /// CBW-004-show_available_chat_models: native menu model projection은 provider와 model 순서 및 handle identity를 보존한다.
    /// 같은 표시 이름을 가진 모델도 handle로 구분하고 unavailable/status 항목은 선택 불가능한 접근성 상태로 노출하는지 검증합니다.
    /// - 검증 내용: provider/model ordering, duplicate title handle identity, single selection, disabled reason,
    /// accessibility metadata
    /// - 사전 조건: provider 순서가 지정되고 같은 이름의 selectable/unavailable 모델과 loading status가 있습니다.
    /// - 기대 결과: 입력 순서와 handle은 유지되고 selected는 하나이며 unavailable/status 항목은 disabled 상태입니다.
    func testNativeMenuModelProjectionPreservesIdentityOrderAndDisabledMetadata() throws {
        let firstHandle = AiModelHandle(provider: .openai, rawValue: "shared-primary")
        let unavailableHandle = AiModelHandle(provider: .openai, rawValue: "shared-unavailable")
        let anthropicHandle = AiModelHandle(provider: .anthropic, rawValue: "shared-anthropic")
        let models = [
            AiProviderModel(
                id: firstHandle,
                provider: .openai,
                rawModelID: firstHandle.rawValue,
                displayName: "Shared model",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unsupported(reason: .init(message: "Thinking unavailable")),
            ),
            AiProviderModel(
                id: unavailableHandle,
                provider: .openai,
                rawModelID: unavailableHandle.rawValue,
                displayName: "Shared model",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unsupported(reason: .init(message: "Thinking unavailable")),
                unavailableReason: .init(message: "Temporarily unavailable"),
            ),
            AiProviderModel(
                id: anthropicHandle,
                provider: .anthropic,
                rawModelID: anthropicHandle.rawValue,
                displayName: "Shared model",
                providerDisplayName: "Anthropic",
                thinkingCapability: .unsupported(reason: .init(message: "Thinking unavailable")),
            ),
        ]
        let rows = [
            AiModelCatalogRow(
                handle: firstHandle,
                displayName: "Shared model",
                authMethod: .apiKey,
                subtitle: nil,
                sortOrder: 10,
                isDefault: true,
                isRecommended: true,
            ),
            AiModelCatalogRow(
                handle: unavailableHandle,
                displayName: "Shared model",
                authMethod: .apiKey,
                subtitle: nil,
                sortOrder: 20,
                isDefault: false,
                isRecommended: false,
            ),
            AiModelCatalogRow(
                handle: anthropicHandle,
                displayName: "Shared model",
                authMethod: .apiKey,
                subtitle: nil,
                sortOrder: 30,
                isDefault: false,
                isRecommended: false,
            ),
        ]
        let state = AiChatFeature.State(
            catalogRows: rows,
            modelListState: .loaded(models),
            selectedModelHandle: firstHandle,
            providerConnectionSnapshot: .known([.anthropic, .openai]),
            availableModelsByProvider: [
                .anthropic: [models[2]],
                .openai: [models[1], models[0]],
            ],
        )

        let sections = state.modelCatalogState.sections
        XCTAssertEqual(sections.map(\.provider), [.anthropic, .openai])
        XCTAssertEqual(sections.map(\.title), ["Anthropic", "OpenAI"])
        XCTAssertEqual(sections[0].rows.map(\.handle), [anthropicHandle])
        XCTAssertEqual(sections[1].rows.map(\.handle), [unavailableHandle, firstHandle])
        XCTAssertEqual(sections.flatMap(\.rows).map(\.title), ["Shared model", "Shared model", "Shared model"])
        XCTAssertEqual(sections.flatMap(\.rows).filter(\.isSelected).map(\.handle), [firstHandle])

        let selectedRow = try XCTUnwrap(sections.flatMap(\.rows).first { $0.handle == firstHandle })
        XCTAssertTrue(selectedRow.isEnabled)
        XCTAssertNil(selectedRow.disabledReason)
        XCTAssertEqual(selectedRow.accessibilityLabel, "Shared model")
        XCTAssertEqual(selectedRow.accessibilityValue, "Selected")

        let unavailableRow = try XCTUnwrap(sections.flatMap(\.rows).first { $0.handle == unavailableHandle })
        XCTAssertFalse(unavailableRow.isEnabled)
        XCTAssertFalse(unavailableRow.isSelected)
        XCTAssertEqual(unavailableRow.disabledReason, "Temporarily unavailable")
        XCTAssertEqual(unavailableRow.accessibilityLabel, "Shared model")
        XCTAssertEqual(unavailableRow.accessibilityValue, "Unavailable: Temporarily unavailable")

        guard case let .loading(status) = AiChatFeature.State(modelListState: .loading).modelSelectorContentState else {
            return XCTFail("Expected loading model selector status")
        }
        XCTAssertFalse(status.isEnabled)
        XCTAssertFalse(status.isSelected)
        XCTAssertEqual(status.disabledReason, "Fetching available models from connected providers.")
        XCTAssertEqual(status.accessibilityLabel, "Loading models")
        XCTAssertEqual(status.accessibilityValue, "Fetching available models from connected providers.")
    }

    // MARK: - CBW-004-select_chat_model_thinking

    /// CBW-004-select_chat_model_thinking: native menu Thinking projection은 policy option과 associated value identity를
    /// 그대로 보존한다.
    /// provider default와 none을 구분하고 unsupported model 및 no-model 상태가 서로 다른 disabled projection인지 검증합니다.
    /// - 검증 내용: policy option/order, selection identity, single selection, unsupported item metadata, no-model trigger
    /// state
    /// - 사전 조건: none을 지원하는 effort model, unsupported model, 선택 model이 없는 loaded state가 있습니다.
    /// - 기대 결과: 지원 model은 policy와 동일한 항목을 제공하고 unsupported/no-model 상태는 선택 동작을 제공하지 않습니다.
    func testNativeMenuThinkingProjectionMirrorsPolicyAndDisabledStates() throws {
        let handle = AiModelHandle(provider: .openai, rawValue: "thinking-model")
        let capableModel = AiProviderModel(
            id: handle,
            provider: .openai,
            rawModelID: handle.rawValue,
            displayName: "Thinking model",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: .low),
            supportsThinkingNone: true,
        )
        let row = AiModelCatalogRow(
            handle: handle,
            displayName: capableModel.displayName,
            authMethod: .apiKey,
            subtitle: nil,
            sortOrder: 0,
            isDefault: true,
            isRecommended: true,
        )
        let state = AiChatFeature.State(
            catalogRows: [row],
            modelListState: .loaded([capableModel]),
            selectedModelHandle: handle,
            selectedThinking: AiThinkingSelection.none,
        )
        let expectedOptions = AiThinkingSelectionPolicy.options(
            capability: capableModel.thinkingCapability,
            supportsNone: capableModel.supportsThinkingNone,
        )

        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems.map(\.selection),
            expectedOptions.map(\.selection),
        )
        let thinkingMenuItems = AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems
        XCTAssertEqual(thinkingMenuItems.map(\.title), expectedOptions.map(\.title))
        XCTAssertEqual(thinkingMenuItems.map(\.id), expectedOptions.map(\.selection))
        XCTAssertEqual(Set(thinkingMenuItems.map(\.id)).count, thinkingMenuItems.count)
        XCTAssertNil(thinkingMenuItems.first?.id)
        XCTAssertEqual(thinkingMenuItems[1].id, AiThinkingSelection.none)
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems.filter(\.isSelected).map(\.selection),
            [AiThinkingSelection.none],
        )
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems.first?.accessibilityValue,
            "Not selected",
        )
        XCTAssertEqual(AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems[1].accessibilityValue, "Selected")
        XCTAssertFalse(AiChatStateDisplayModelBuilder(state: state).thinkingMenuIsDisabled)

        let unavailableCapabilities: [(AiModelThinkingCapability, String)] = [
            (
                .unsupported(reason: .init(message: "Thinking is unavailable for this model.")),
                "Thinking is unavailable for this model.",
            ),
            (
                .unknown(reason: .init(message: "Thinking metadata is not loaded yet.")),
                "Thinking metadata is not loaded yet.",
            ),
        ]
        for (capability, unavailableReason) in unavailableCapabilities {
            let unavailableModel = AiProviderModel(
                id: handle,
                provider: .openai,
                rawModelID: handle.rawValue,
                displayName: "Thinking model",
                providerDisplayName: "OpenAI",
                thinkingCapability: capability,
            )
            let unavailableState = AiChatFeature.State(
                catalogRows: [row],
                modelListState: .loaded([unavailableModel]),
                selectedModelHandle: handle,
            )
            let unavailableProjection = AiChatStateDisplayModelBuilder(state: unavailableState)
            XCTAssertEqual(unavailableProjection.thinkingMenuItems.count, 1)
            let unavailableItem = try XCTUnwrap(unavailableProjection.thinkingMenuItems.first)
            XCTAssertNil(unavailableItem.id)
            XCTAssertNil(unavailableItem.selection)
            XCTAssertEqual(unavailableItem.title, "Thinking unavailable")
            XCTAssertFalse(unavailableItem.isEnabled)
            XCTAssertFalse(unavailableItem.isSelected)
            XCTAssertEqual(unavailableItem.disabledReason, unavailableReason)
            XCTAssertEqual(unavailableItem.accessibilityLabel, "Thinking unavailable")
            XCTAssertEqual(unavailableItem.accessibilityValue, "Unavailable: \(unavailableReason)")
            XCTAssertFalse(unavailableProjection.thinkingMenuIsDisabled)
        }

        let noModelState = AiChatFeature.State(modelListState: .loaded([]))
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: noModelState).thinkingMenuItems.isEmpty)
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: noModelState).thinkingMenuIsDisabled)
    }

    /// CBW-004-select_chat_model_thinking: 범위 밖 token default는 enabled native menu 항목에서 제외한다.
    /// provider가 최소값 아래나 최대값 위 default를 보내도 reducer가 수용하는 경계 선택지만 노출하는지 검증합니다.
    /// - 검증 내용: below-min/above-max default의 enabled menu item 부재와 provider-default/min/max ordering
    /// - 사전 조건: 128...1024 범위에 default 64 또는 2048인 token budget model이 선택되어 있습니다.
    /// - 기대 결과: 각 menu에는 provider default, 128, 1024만 enabled 상태로 순서대로 존재합니다.
    func testNativeMenuThinkingProjectionOmitsOutOfRangeTokenDefaults() {
        let handle = AiModelHandle(provider: .openai, rawValue: "out-of-range-default-model")
        let row = AiModelCatalogRow(
            handle: handle,
            displayName: "Out-of-range default model",
            authMethod: .apiKey,
            subtitle: nil,
            sortOrder: 0,
            isDefault: true,
            isRecommended: true,
        )

        for invalidDefault in [64, 2048] {
            let model = AiProviderModel(
                id: handle,
                provider: .openai,
                rawModelID: handle.rawValue,
                displayName: row.displayName,
                providerDisplayName: "OpenAI",
                thinkingCapability: .tokenBudget(min: 128, max: 1024, defaultValue: invalidDefault),
            )
            let state = AiChatFeature.State(
                catalogRows: [row],
                modelListState: .loaded([model]),
                selectedModelHandle: handle,
            )
            let enabledSelections = AiChatStateDisplayModelBuilder(state: state).thinkingMenuItems
                .filter(\.isEnabled)
                .map(\.selection)

            XCTAssertEqual(enabledSelections, [nil, .tokenBudget(128), .tokenBudget(1024)])
            XCTAssertFalse(enabledSelections.contains(.tokenBudget(invalidDefault)))
        }
    }

    /// CBW-004-select_chat_model_thinking: 역전된 token budget metadata는 선택지를 만들거나 정규화하지 않는다.
    /// provider metadata의 최소 token이 최대 token보다 큰 경우에도 정책이 안전하게 fail closed 하는지 검증합니다.
    /// - 검증 내용: malformed token budget options와 non-nil selection normalization
    /// - 사전 조건: minimumTokens 1024, maximumTokens 128인 token budget capability
    /// - 기대 결과: options는 비어 있고 non-nil token budget selection은 nil로 정규화된다.
    func testMalformedThinkingTokenBudgetPolicyFailsClosed() {
        let capability = AiModelThinkingCapability.tokenBudget(min: 1024, max: 128, defaultValue: 512)

        XCTAssertTrue(AiThinkingSelectionPolicy.options(
            capability: capability,
            supportsNone: true,
        ).isEmpty)
        XCTAssertNil(AiThinkingSelectionPolicy.normalize(
            .tokenBudget(512),
            capability: capability,
            supportsNone: true,
        ))
        XCTAssertNil(AiThinkingSelectionPolicy.normalize(
            AiThinkingSelection.none,
            capability: capability,
            supportsNone: true,
        ))
    }

    /// CBW-004-select_chat_model_thinking: malformed token budget model은 비활성 unavailable 항목만 노출한다.
    /// stale UI가 유효하지 않은 Thinking 값을 직접 보내도 feature 상태와 effect가 그대로 유지되는지 검증합니다.
    /// - 검증 내용: unavailable projection metadata와 invalid selectedThinkingChanged의 full-state/effect no-op
    /// - 사전 조건: malformed token budget model과 untouched transient session이 선택된 상태
    /// - 기대 결과: action-free unavailable 항목 하나만 보이고 invalid action은 어떤 상태나 effect도 바꾸지 않는다.
    func testMalformedThinkingTokenBudgetProjectsUnavailableAndRejectsDirectSelection() async throws {
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114005"))
        let handle = AiModelHandle(provider: .openai, rawValue: "malformed-thinking-model")
        let model = AiProviderModel(
            id: handle,
            provider: .openai,
            rawModelID: handle.rawValue,
            displayName: "Malformed Thinking model",
            providerDisplayName: "OpenAI",
            thinkingCapability: .tokenBudget(min: 1024, max: 128, defaultValue: 512),
            supportsThinkingNone: true,
        )
        let row = AiModelCatalogRow(
            handle: handle,
            displayName: model.displayName,
            authMethod: .apiKey,
            subtitle: nil,
            sortOrder: 0,
            isDefault: true,
            isRecommended: true,
        )
        let initialState = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            preparedTransientSessionID: sessionID,
            catalogRows: [row],
            modelListState: .loaded([model]),
            selectedModelHandle: handle,
        )
        let projection = AiChatStateDisplayModelBuilder(state: initialState)

        XCTAssertFalse(projection.thinkingMenuIsDisabled)
        XCTAssertEqual(projection.thinkingMenuItems.count, 1)
        let item = try XCTUnwrap(projection.thinkingMenuItems.first)
        XCTAssertNil(item.selection)
        XCTAssertEqual(item.title, "Thinking unavailable")
        XCTAssertFalse(item.isSelected)
        XCTAssertFalse(item.isEnabled)

        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }
        await store.send(.selectedThinkingChanged(.tokenBudget(512)))
        XCTAssertEqual(store.state, initialState)
        await store.finish()
    }

    /// CBW-004-show_unavailable_chat_model_state: 같은 handle이 unavailable로 갱신되면 draft 선택을 해제한다.
    /// catalog refresh가 선택 불가능한 모델을 draft 경계에서 제거하고 기존 복구 handle만 보존하는지 검증합니다.
    /// - 검증 내용: selected model/thinking clear, unavailable recovery handle, submit/regenerate gate
    /// - 사전 조건: assistant transcript와 선택 모델이 있고 같은 handle의 모델이 unavailable로 다시 loaded 됩니다.
    /// - 기대 결과: 자동 fallback 없이 draft 선택이 해제되고 submit/regenerate가 모두 비활성화됩니다.
    func testUnavailableRefreshClearsDraftSelectionAndSubmissionGates() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let unavailableModel = makeCBW004UnavailableModel(selectedModel)
        let requestID = makeUUID("00000000-0000-0000-0000-000000004101")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114101")),
            sessionStatus: .active,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question"),
                AiChatMessage(role: .assistant, content: "Answer"),
            ],
            draftText: "Next question",
            catalogRows: [makeCatalogRows()[0]],
            modelListState: .loaded([selectedModel]),
            selectedModelHandle: selectedModel.id,
            selectedThinking: .effort(.high),
            modelListRequestID: requestID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: catalog batch bookkeeping보다 draft availability 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: [unavailableModel],
        ))

        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertNil(store.state.selectedThinking)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, selectedModel.id)
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertFalse(store.state.canRegenerate)
    }

    /// CBW-004-show_unavailable_chat_model_state: stale unavailable 선택과 실행 action은 새 요청을 만들지 않는다.
    /// 비활성 row의 stale action과 직접 submit/regenerate가 domain availability를 우회하지 않는지 검증합니다.
    /// - 검증 내용: direct selection no-op, canSubmit/canRegenerate false, pending/lock/request 미생성
    /// - 사전 조건: loaded catalog에 unavailable 모델만 있고 draft와 assistant transcript가 존재합니다.
    /// - 기대 결과: 모델은 선택되지 않고 submit/regenerate 모두 effect나 request를 시작하지 않습니다.
    func testUnavailableModelCannotBeSelectedOrStartFreshRequest() async {
        let availableModel = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(availableModel)
        let stream = AiChatExecutionStreamDriver()
        let initialState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114102")),
            sessionStatus: .active,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question"),
                AiChatMessage(role: .assistant, content: "Answer"),
            ],
            draftText: "Next question",
            catalogRows: [makeCatalogRows()[0]],
            modelListState: .loaded([unavailableModel]),
            selectedModelHandle: nil,
            providerConnectionSnapshot: .known([.openai]),
        )
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
            $0.aiChatContextPartResolverClient = .init { _ in
                AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
            }
        }
        // store.exhaustivity = .off: stale action과 request guard의 완전한 no-op만 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.selectedModelChanged(unavailableModel.id))
        XCTAssertEqual(store.state, initialState)
        XCTAssertFalse(store.state.canSubmit)
        XCTAssertFalse(store.state.canRegenerate)

        await store.send(.submitTapped)
        await store.send(.regenerateTapped)

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: pending context 완료는 최신 availability를 다시 검증한다.
    /// 요청 준비 후 catalog가 unavailable로 바뀐 race에서 승인된 pending snapshot을 재작성하지 않는지 검증합니다.
    /// - 검증 내용: refresh 중 pending Equatable 보존, completion 후 lock/request 미생성
    /// - 사전 조건: available 모델로 승인된 pending request와 같은 handle의 unavailable refresh가 존재합니다.
    /// - 기대 결과: refresh는 pending을 그대로 두고 resolution completion은 이를 소비하되 새 lock을 만들지 않습니다.
    func testUnavailableRefreshPreventsPendingContextResolutionFromCreatingLock() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(model)
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004103")
        let refreshID = makeUUID("00000000-0000-0000-0000-000000004104")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114103"))
        let message = AiChatMessage(role: .user, content: "Pending request")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: model,
            selectedRow: row,
            selectedThinking: .effort(.medium),
            preparedRequest: AiChatPreparedRequest(
                prompt: message.content,
                messages: [message],
                persistenceTranscriptHistory: [message],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            catalogRows: [row],
            modelListState: .loaded([model]),
            selectedModelHandle: model.id,
            selectedThinking: .effort(.medium),
            pendingRequestStart: pendingRequest,
            modelListRequestID: refreshID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: pending snapshot 보존과 lock 미생성 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoaded(
            requestID: refreshID,
            provider: .openai,
            models: [unavailableModel],
        ))
        XCTAssertEqual(store.state.pendingRequestStart, pendingRequest)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: 선택 provider 부분 완료 unavailable은 foreground lock을 막는다.
    /// aggregate loading이어도 선택 provider의 성공 결과가 확정되면 stale approved snapshot을 실행하지 않는지 검증합니다.
    /// - 검증 내용: foreground pending 소비 후 lock/request 미생성
    /// - 사전 조건: OpenAI unavailable 결과가 완료되었고 Anthropic만 pending인 multi-provider refresh입니다.
    /// - 기대 결과: resolution completion은 pending을 소비하되 unavailable OpenAI request를 시작하지 않습니다.
    func testPartialProviderUnavailableCompletionPreventsPendingContextResolutionFromCreatingLock() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(model)
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004109")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114109"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: sessionID,
            model: model,
            row: row,
            prompt: "Partial foreground pending request",
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            modelListState: .loading,
            pendingRequestStart: pendingRequest,
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.anthropic],
            modelListLoadedModelsByProvider: [.openai: [unavailableModel]],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_109))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: provider별 부분 완료에서 lock 미생성 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: 선택 provider 부분 완료 unavailable은 background lock을 막는다.
    /// background pending dictionary도 provider별 authoritative 결과로 stale approved snapshot을 차단하는지 검증합니다.
    /// - 검증 내용: background pending 소비 후 background lock/request 미생성
    /// - 사전 조건: OpenAI unavailable 결과가 완료되었고 Anthropic만 pending인 multi-provider refresh입니다.
    /// - 기대 결과: resolution completion은 pending을 소비하되 background execution phase를 만들지 않습니다.
    func testPartialProviderUnavailableCompletionPreventsBackgroundPendingContextResolutionFromCreatingLock() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(model)
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004110")
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114110"))
        let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222224110"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: backgroundSessionID,
            model: model,
            row: row,
            prompt: "Partial background pending request",
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            sessionStatus: .active,
            modelListState: .loading,
            backgroundPendingRequestStarts: [resolutionID: pendingRequest],
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.anthropic],
            modelListLoadedModelsByProvider: [.openai: [unavailableModel]],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_110))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: provider별 부분 완료에서 background lock 미생성 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertTrue(store.state.backgroundExecutionPhases.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: known 연결 목록에 없는 provider는 foreground pending을 거부한다.
    /// catalog 결과가 미완료여도 연결 authority가 선택 provider의 부재를 확정하는지 검증합니다.
    /// - 검증 내용: known-disconnected provider의 foreground pending 소비 후 lock/request 미생성
    /// - 사전 조건: OpenAI frozen pending이 있고 known 연결 목록에는 Anthropic만 있습니다.
    /// - 기대 결과: resolution completion은 pending을 소비하되 OpenAI request를 시작하지 않습니다.
    func testKnownDisconnectedProviderPreventsForegroundPendingContextResolutionFromCreatingLock() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004116")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114116"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: sessionID,
            model: selectedModel,
            row: row,
            prompt: "Known disconnected foreground request",
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            modelListState: .loading,
            pendingRequestStart: pendingRequest,
            modelListPendingProviders: [.openai],
            providerConnectionSnapshot: .known([.anthropic]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_116))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: known-disconnected foreground pending의 거부 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: known 연결 목록에 없는 provider는 background pending을 거부한다.
    /// foreground와 분리된 background owner도 같은 canonical connection authority를 적용하는지 검증합니다.
    /// - 검증 내용: known-disconnected provider의 background pending 소비 후 lock/request 미생성
    /// - 사전 조건: OpenAI frozen background pending이 있고 known 연결 목록에는 Anthropic만 있습니다.
    /// - 기대 결과: resolution completion은 pending을 소비하되 background execution phase를 만들지 않습니다.
    func testKnownDisconnectedProviderPreventsBackgroundPendingContextResolutionFromCreatingLock() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004117")
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114117"))
        let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222224117"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: backgroundSessionID,
            model: selectedModel,
            row: row,
            prompt: "Known disconnected background request",
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            sessionStatus: .active,
            modelListState: .loading,
            backgroundPendingRequestStarts: [resolutionID: pendingRequest],
            modelListFailedProviders: [.openai: .init(message: "Stale OpenAI listing failure")],
            providerConnectionSnapshot: .known([.anthropic]),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_117))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: known-disconnected background pending의 거부 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertTrue(store.state.backgroundExecutionPhases.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: 선택 provider failure-only는 unavailable 확정이 아니다.
    /// 성공한 provider catalog가 없는 실패 결과만으로 approved frozen snapshot을 폐기하지 않는지 검증합니다.
    /// - 검증 내용: failure-only loading 중 foreground request/lock 생성
    /// - 사전 조건: OpenAI load는 실패했고 Anthropic만 pending인 multi-provider refresh입니다.
    /// - 기대 결과: resolution completion은 frozen OpenAI snapshot으로 기존 요청을 시작합니다.
    func testPartialProviderFailureDoesNotDropApprovedPendingContextResolution() async {
        let model = makeThinkingCapableProviderModels()[0]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004111")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114111"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: sessionID,
            model: model,
            row: row,
            prompt: "Failed provider pending request",
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            modelListState: .loading,
            pendingRequestStart: pendingRequest,
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.anthropic],
            modelListFailedProviders: [.openai: .init(message: "OpenAI model list request failed.")],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_111))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: failure-only refresh에서 approved pending 실행 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(stream.requests.count, 1)
        XCTAssertEqual(stream.requests.first?.context.selectedModel, model)
        if case let .processing(lock) = store.state.executionPhase {
            XCTAssertEqual(lock.selectedModelHandle, model.id)
            XCTAssertEqual(lock.context.selectedModel, model)
        } else {
            XCTFail("failure-only provider result should preserve the approved pending request")
        }
    }

    /// CBW-004-show_unavailable_chat_model_state: 선택 provider failure 뒤 다른 provider 성공은 foreground pending을 보존한다.
    /// 최종 aggregate가 다른 provider 모델만 포함해도 실패 provider의 absence를 unavailable로 확정하지 않는지 검증합니다.
    /// - 검증 내용: failure → success 완료 순서, final loaded aggregate, frozen foreground request/lock 생성
    /// - 사전 조건: OpenAI frozen pending이 있고 OpenAI 실패 뒤 Anthropic 성공으로 batch가 완료됩니다.
    /// - 기대 결과: pending은 완료 전까지 보존되고 context resolution은 원래 OpenAI 모델 metadata로 요청을 시작합니다.
    func testSelectedProviderFailureThenOtherProviderSuccessPreservesForegroundPendingRequest() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let otherProviderModel = models[1]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004112")
        let batchID = makeUUID("00000000-0000-0000-0000-000000004113")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114112"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: sessionID,
            model: selectedModel,
            row: row,
            prompt: "Failure then success foreground request",
        )
        let stream = AiChatExecutionStreamDriver()
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            modelListState: .loading,
            pendingRequestStart: pendingRequest,
            modelListRequestID: batchID,
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.openai, .anthropic],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_112))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: provider 완료 순서와 frozen foreground request 시작 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoadFailed(
            requestID: batchID,
            provider: .openai,
            failure: failure,
        ))
        XCTAssertEqual(store.state.pendingRequestStart, pendingRequest)

        await store.send(.modelListLoaded(
            requestID: batchID,
            provider: .anthropic,
            models: [otherProviderModel],
        ))
        XCTAssertEqual(store.state.modelListState, .loaded([otherProviderModel]))
        XCTAssertEqual(store.state.modelListFailedProviders, [.openai: failure])
        XCTAssertEqual(store.state.pendingRequestStart, pendingRequest)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(stream.requests.first?.context.selectedModel, selectedModel)
        if case let .processing(lock) = store.state.executionPhase {
            XCTAssertEqual(lock.context.selectedModel, selectedModel)
            XCTAssertEqual(lock.selectedModelHandle, selectedModel.id)
        } else {
            XCTFail("provider failure must not consume the approved foreground request")
        }
    }

    /// CBW-004-show_unavailable_chat_model_state: 다른 provider 성공 뒤 선택 provider failure는 background pending을 보존한다.
    /// provider completion 역순에서도 failure evidence가 final aggregate absence보다 우선하는지 검증합니다.
    /// - 검증 내용: success → failure 완료 순서, final loaded aggregate, frozen background request/lock 생성
    /// - 사전 조건: OpenAI frozen background pending이 있고 Anthropic 성공 뒤 OpenAI 실패로 batch가 완료됩니다.
    /// - 기대 결과: context resolution은 background pending을 원래 OpenAI 모델 metadata로 시작합니다.
    func testOtherProviderSuccessThenSelectedProviderFailurePreservesBackgroundPendingRequest() async {
        let models = makeThinkingCapableProviderModels()
        let selectedModel = models[0]
        let otherProviderModel = models[1]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004114")
        let batchID = makeUUID("00000000-0000-0000-0000-000000004115")
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114114"))
        let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222224114"))
        let pendingRequest = makeCBW004PendingRequest(
            resolutionID: resolutionID,
            sessionID: backgroundSessionID,
            model: selectedModel,
            row: row,
            prompt: "Success then failure background request",
        )
        let stream = AiChatExecutionStreamDriver()
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            sessionStatus: .active,
            modelListState: .loading,
            backgroundPendingRequestStarts: [resolutionID: pendingRequest],
            modelListRequestID: batchID,
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.openai, .anthropic],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_114))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: provider 완료 역순과 frozen background request 시작 경계만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoaded(
            requestID: batchID,
            provider: .anthropic,
            models: [otherProviderModel],
        ))
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pendingRequest)

        await store.send(.modelListLoadFailed(
            requestID: batchID,
            provider: .openai,
            failure: failure,
        ))
        XCTAssertEqual(store.state.modelListState, .loaded([otherProviderModel]))
        XCTAssertEqual(store.state.modelListFailedProviders, [.openai: failure])
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pendingRequest)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(stream.requests.first?.context.selectedModel, selectedModel)
        guard let phase = store.state.backgroundExecutionPhases.values.first,
              case let .processing(lock) = phase
        else {
            return XCTFail("provider failure must not consume the approved background request")
        }
        XCTAssertEqual(lock.context.selectedModel, selectedModel)
        XCTAssertEqual(lock.selectedModelHandle, selectedModel.id)
    }

    /// CBW-004-show_unavailable_chat_model_state: loading은 승인된 pending 모델의 unavailable 확정이 아니다.
    /// context resolution과 catalog refresh가 겹쳐도 마지막 approved snapshot이 조용히 소실되지 않는지 검증합니다.
    /// - 검증 내용: loading 중 foreground pending 소비와 frozen model request/lock 생성
    /// - 사전 조건: available 모델로 승인된 pending request 이후 catalog refresh가 loading 상태입니다.
    /// - 기대 결과: resolution completion은 frozen pending으로 기존 요청을 시작하고 같은 모델 lock을 만듭니다.
    func testCatalogLoadingDoesNotDropApprovedPendingContextResolution() async {
        let model = makeThinkingCapableProviderModels()[0]
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004106")
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114106"))
        let message = AiChatMessage(role: .user, content: "Approved pending request")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: model,
            selectedRow: row,
            preparedRequest: AiChatPreparedRequest(
                prompt: message.content,
                messages: [message],
                persistenceTranscriptHistory: [message],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            catalogRows: [row],
            modelListState: .loading,
            pendingRequestStart: pendingRequest,
            modelListProviderOrder: [.openai, .anthropic],
            modelListPendingProviders: [.openai],
            modelListLoadedModelsByProvider: [.anthropic: []],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_004_106))
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: loading race에서 approved pending의 요청 시작만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.pendingRequestStart)
        XCTAssertEqual(stream.requests.count, 1)
        XCTAssertEqual(stream.requests.first?.context.selectedModel, model)
        if case let .processing(lock) = store.state.executionPhase {
            XCTAssertEqual(lock.selectedModelHandle, model.id)
            XCTAssertEqual(lock.context.selectedModel, model)
        } else {
            XCTFail("approved pending request should start while catalog refresh is unresolved")
        }
    }

    /// CBW-004-show_unavailable_chat_model_state: background pending도 unavailable refresh를 lock 없이 종료한다.
    /// foreground와 별도 dictionary owner인 background resolution 경계가 canonical availability를 우회하지 않는지 검증합니다.
    /// - 검증 내용: refresh 중 background pending Equatable 보존, completion 후 background lock/request 미생성
    /// - 사전 조건: 다른 session의 approved pending과 같은 handle이 unavailable로 refresh 됩니다.
    /// - 기대 결과: refresh는 pending을 재작성하지 않고 completion은 이를 소비하되 어떤 execution phase도 만들지 않습니다.
    func testUnavailableRefreshPreventsBackgroundPendingContextResolutionFromCreatingLock() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(model)
        let row = makeCatalogRows()[0]
        let resolutionID = makeUUID("00000000-0000-0000-0000-000000004107")
        let refreshID = makeUUID("00000000-0000-0000-0000-000000004108")
        let visibleSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114107"))
        let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222224107"))
        let message = AiChatMessage(role: .user, content: "Background pending request")
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: backgroundSessionID,
            selectedModel: model,
            selectedRow: row,
            preparedRequest: AiChatPreparedRequest(
                prompt: message.content,
                messages: [message],
                persistenceTranscriptHistory: [message],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        let stream = AiChatExecutionStreamDriver()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: visibleSessionID,
            sessionStatus: .active,
            catalogRows: [row],
            modelListState: .loaded([model]),
            backgroundPendingRequestStarts: [resolutionID: pendingRequest],
            modelListRequestID: refreshID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = .init { request in
                stream.stream(for: request)
            }
        }
        // store.exhaustivity = .off: background pending snapshot 보존과 lock 미생성만 선별 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoaded(
            requestID: refreshID,
            provider: .openai,
            models: [unavailableModel],
        ))
        XCTAssertEqual(store.state.backgroundPendingRequestStarts[resolutionID], pendingRequest)

        await store.send(.requestContextResolved(
            resolutionID,
            AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: []),
        ))

        XCTAssertNil(store.state.backgroundPendingRequestStarts[resolutionID])
        XCTAssertTrue(store.state.backgroundExecutionPhases.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertTrue(stream.requests.isEmpty)
    }

    /// CBW-004-show_unavailable_chat_model_state: connection authority 갱신은 active request lock을 바꾸지 않는다.
    /// provider 연결 snapshot만 교체하고 request-scoped execution truth는 유지하는지 검증합니다.
    /// - 검증 내용: authority snapshot 변경과 foreground/background lock의 완전한 불변성
    /// - 사전 조건: foreground와 background request가 실행 중이고 OpenAI/Anthropic 연결 snapshot이 있습니다.
    /// - 기대 결과: snapshot만 Anthropic으로 바뀌고 두 execution phase와 locked handle은 동일합니다.
    func testProviderConnectionAuthorityUpdatePreservesActiveRequestLocks() async {
        let initialState = makeCBW004SelectionBookkeepingState(models: makeThinkingCapableProviderModels())
        let lockedModelHandle = initialState.lockedModelHandle
        let executionPhase = initialState.executionPhase
        let backgroundExecutionPhases = initialState.backgroundExecutionPhases
        let store = TestStore(initialState: initialState) {
            AiChatFeature()
        }

        await store.send(.providerConnectionAuthorityUpdated([.anthropic])) { state in
            state.providerConnectionSnapshot = .known([.anthropic])
        }

        XCTAssertEqual(store.state.lockedModelHandle, lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, executionPhase)
        XCTAssertEqual(store.state.backgroundExecutionPhases, backgroundExecutionPhases)
        await store.finish()
    }

    /// CBW-004-show_unavailable_chat_model_state: catalog availability 변경은 active request lock을 바꾸지 않는다.
    /// draft 모델이 unavailable로 바뀌어도 이미 processing 중인 request-scoped truth가 유지되는지 검증합니다.
    /// - 검증 내용: processing lock과 background execution snapshot의 Equatable 불변성
    /// - 사전 조건: 선택 모델로 foreground lock이 processing 중이고 같은 handle이 unavailable로 refresh 됩니다.
    /// - 기대 결과: draft 선택만 복구 상태로 이동하고 기존 lock과 processing phase는 동일합니다.
    func testUnavailableRefreshPreservesActiveRequestLockExactly() async {
        let model = makeThinkingCapableProviderModels()[0]
        let unavailableModel = makeCBW004UnavailableModel(model)
        let row = makeCatalogRows()[0]
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114104"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224104")),
                runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334104")),
                model: model.id,
                selectedRow: row,
                selectedModel: model,
                selectedThinking: .effort(.medium),
            ),
            messages: [AiChatMessage(role: .user, content: "Locked request")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: model.id,
            selectedRow: row,
            assistantReplacementIndex: nil,
        )
        let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444104"))
        let backgroundRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: backgroundSessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("55555555-5555-5555-5555-555555554104")),
                runID: AiChatRunID(rawValue: makeUUID("66666666-6666-6666-6666-666666664104")),
                model: model.id,
                selectedRow: row,
                selectedModel: model,
                selectedThinking: .effort(.medium),
            ),
            messages: [AiChatMessage(role: .user, content: "Background locked request")],
        )
        let backgroundLock = makeRequestLock(
            kind: .submit,
            request: backgroundRequest,
            selectedHandle: model.id,
            selectedRow: row,
            assistantReplacementIndex: nil,
        )
        let backgroundExecutionPhases = [backgroundLock.requestID: AiChatExecutionPhase.processing(backgroundLock)]
        let refreshID = makeUUID("00000000-0000-0000-0000-000000004105")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            catalogRows: [row],
            modelListState: .loaded([model]),
            selectedModelHandle: model.id,
            selectedThinking: .effort(.medium),
            lockedModelHandle: model.id,
            executionPhase: .processing(lock),
            backgroundExecutionPhases: backgroundExecutionPhases,
            modelListRequestID: refreshID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )) {
            AiChatFeature()
        }
        // store.exhaustivity = .off: catalog bookkeeping을 제외하고 request lock의 완전한 불변성만 검증합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.modelListLoaded(
            requestID: refreshID,
            provider: .openai,
            models: [unavailableModel],
        ))

        XCTAssertEqual(store.state.executionPhase, .processing(lock))
        XCTAssertEqual(store.state.backgroundExecutionPhases, backgroundExecutionPhases)
        XCTAssertEqual(store.state.lockedModelHandle, model.id)
        XCTAssertNil(store.state.selectedModelHandle)
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, model.id)
    }
}

private func makeCBW004SelectionBookkeepingState(models: [AiProviderModel]) -> AiChatFeature.State {
    let catalogRows = makeCatalogRows()
    let selectedModel = models[0]
    let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114201"))
    let foregroundRequest = AiChatRequest(
        context: makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222224201")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333334201")),
            model: selectedModel.id,
            selectedRow: catalogRows[0],
            selectedModel: selectedModel,
            selectedThinking: .effort(.high),
        ),
        messages: [AiChatMessage(role: .user, content: "Foreground request")],
    )
    let foregroundLock = makeRequestLock(
        kind: .submit,
        request: foregroundRequest,
        selectedHandle: selectedModel.id,
        selectedRow: catalogRows[0],
        assistantReplacementIndex: nil,
    )
    let backgroundSessionID = AiChatSessionID(rawValue: makeUUID("44444444-4444-4444-4444-444444444201"))
    let backgroundRequest = AiChatRequest(
        context: makeRequestContext(
            sessionID: backgroundSessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("55555555-5555-5555-5555-555555554201")),
            runID: AiChatRunID(rawValue: makeUUID("66666666-6666-6666-6666-666666664201")),
            model: selectedModel.id,
            selectedRow: catalogRows[0],
            selectedModel: selectedModel,
            selectedThinking: .effort(.high),
        ),
        messages: [AiChatMessage(role: .user, content: "Background request")],
    )
    let backgroundLock = makeRequestLock(
        kind: .submit,
        request: backgroundRequest,
        selectedHandle: selectedModel.id,
        selectedRow: catalogRows[0],
        assistantReplacementIndex: nil,
    )

    return AiChatFeature.State(
        mode: .chat,
        sessionID: sessionID,
        preparedTransientSessionID: sessionID,
        sessionStatus: .active,
        currentContext: makeContextSnapshot(),
        transcriptHistory: [AiChatMessage(role: .user, content: "Draft context")],
        draftText: "Draft",
        catalogRows: catalogRows,
        modelListState: .loaded(models),
        selectedModelHandle: selectedModel.id,
        selectedThinking: .effort(.high),
        unavailableSelectedModelHandle: makeUnresolvableModelHandle(),
        lockedModelHandle: selectedModel.id,
        lastExecutionFailure: .unsupportedProvider,
        executionPhase: .processing(foregroundLock),
        backgroundExecutionPhases: [
            backgroundLock.requestID: .failed(backgroundLock, .unsupportedProvider),
        ],
        providerConnectionSnapshot: .known([.openai, .anthropic]),
    )
}

private func makeCBW004PendingRequest(
    resolutionID: UUID,
    sessionID: AiChatSessionID,
    model: AiProviderModel,
    row: AiModelCatalogRow,
    prompt: String,
) -> AiChatPendingRequestStart {
    let message = AiChatMessage(role: .user, content: prompt)
    return AiChatPendingRequestStart(
        resolutionID: resolutionID,
        kind: .submit,
        sessionID: sessionID,
        selectedModel: model,
        selectedRow: row,
        preparedRequest: AiChatPreparedRequest(
            prompt: prompt,
            messages: [message],
            persistenceTranscriptHistory: [message],
            assistantReplacementIndex: nil,
            historyTruncation: .init(
                includedMessageCount: 1,
                excludedMessageCount: 0,
                budget: 24000,
                truncationReason: nil,
            ),
        ),
    )
}

private func makeCBW004UnavailableModel(_ model: AiProviderModel) -> AiProviderModel {
    AiProviderModel(
        id: model.id,
        provider: model.provider,
        rawModelID: model.rawModelID,
        displayName: model.displayName,
        providerDisplayName: model.providerDisplayName,
        thinkingCapability: model.thinkingCapability,
        supportsThinkingNone: model.supportsThinkingNone,
        unavailableReason: .init(message: "Model is temporarily unavailable."),
    )
}

@MainActor
private func applyCBW004ObservationFocusedExhaustivity(
    to store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
) {
    // 사용자에게 보이는 model selection과 provider request snapshot을 중심으로 검증하기 위해 exhaustivity를 낮춥니다.
    store.exhaustivity = .off(showSkippedAssertions: false)
}

private struct CBW004SubmitFixture {
    let store: TestStore<AiChatFeature.State, AiChatFeature.Action>
    let stream: AiChatExecutionStreamDriver
    let catalogRows: [AiModelCatalogRow]
    let models: [AiProviderModel]
}

@MainActor
private func makeCBW004SubmitFixture(
    draftText: String,
    selectedHandle: AiModelHandle,
    selectedThinking: AiThinkingSelection?,
    fixedMs: Int64,
) -> CBW004SubmitFixture {
    let catalogRows = makeCatalogRows()
    let models = makeThinkingCapableProviderModels()
    let stream = AiChatExecutionStreamDriver()
    let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111114004"))
    let store = TestStore(initialState: AiChatFeature.State(
        sessionID: sessionID,
        sessionStatus: .active,
        currentContext: makeContextSnapshot(),
        transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
        draftText: draftText,
        catalogRows: catalogRows,
        modelListState: .loaded(models),
        selectedModelHandle: selectedHandle,
        selectedThinking: selectedThinking,
        lockedModelHandle: nil,
        lastExecutionFailure: nil,
        executionPhase: .idle,
        providerConnectionSnapshot: .known([.openai, .anthropic]),
    )) {
        AiChatFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
        $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
            stream.stream(for: request)
        })
        $0.aiConnectionsFileClient = AIConnectionsFileClient(
            load: {
                makeConnectionsFile(providers: [
                    makeProviderRecord(
                        provider: .openai,
                        credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    ),
                    makeProviderRecord(
                        provider: .anthropic,
                        credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    ),
                ])
            },
            save: { .success($0) },
            deleteCredential: { _ in .success(.empty()) },
        )
    }

    return CBW004SubmitFixture(
        store: store,
        stream: stream,
        catalogRows: catalogRows,
        models: models,
    )
}

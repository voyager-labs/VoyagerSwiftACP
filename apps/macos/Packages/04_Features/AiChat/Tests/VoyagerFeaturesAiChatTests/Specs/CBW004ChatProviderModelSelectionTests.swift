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

    // MARK: - CBW-004-open_chat_model_selector

    /// CBW-004-open_chat_model_selector: 모델 selector presentation은 선택 상태를 변경하지 않는다.
    /// selector 열기/닫기와 동일 모델 선택이 현재 active model을 오염시키지 않는지 검증합니다.
    /// - 검증 내용: presentation flag toggle, same-model no-op, dismissal behavior
    /// - 사전 조건: 모델 하나가 이미 선택된 active chat 상태
    /// - 기대 결과: selector UI 상태만 바뀌고 selected model handle은 유지된다.
    func testOpenChatModelSelectorTogglesWithoutTouchingSelection() async {
        let catalogRows = [makeCatalogRows()[0]]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
        )) {
            AiChatFeature()
        }

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
        XCTAssertTrue(AiChatModelSelectorLayout.usesScrollableContent(for: state.modelSelectorContentState))
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
        XCTAssertTrue(emptyState.modelSelectorIsDisabled)
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

    /// CBW-004-show_unavailable_chat_model_state: Selected Model Changed Clears Unavailable Selection Without Mutating
    /// Locked Model
    /// CBW-004 AC에 연결되는 legacy 동작을 새 Specs owner suite에서 검증합니다.
    /// - 검증 내용: 기존 legacy 테스트가 검증하던 관찰 가능한 상태와 출력 값을 확인합니다.
    /// - 사전 조건: 기존 테스트 fixture와 dependency 설정을 그대로 사용합니다.
    /// - 기대 결과: CBW AC에 필요한 사용자 관찰 동작이 회귀 없이 유지됩니다.
    func testSelectedModelChangedClearsUnavailableSelectionWithoutMutatingLockedModel() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let unresolvableHandle = makeUnresolvableModelHandle()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
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
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = nil
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[1].handle)
        XCTAssertNil(store.state.selectedModelHandle)

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected processing surface state after clearing invalid selection")
        }
    }
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

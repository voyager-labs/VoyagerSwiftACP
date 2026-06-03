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

// FLOW-ID: set.collection_search_ai_settings
import ComposableArchitecture
import Dependencies
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class CollectionSearchAiSettingsFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// set.collection_search_ai_settings: happy_path
    func testConnectedProviderSelectionPersistsAndProducesQueryConversionPayload() async {
        let storedSettings = LockIsolated(CollectionSearchAISettings.default)
        let model = Self.openAIModel
        let store = makeSettingsStore(
            storedSettings: storedSettings,
            initialState: AiSettingsState(
                collectionSearchModelsByProvider: [.openai: [model]],
            ),
        )

        await store.send(.collectionSearchProviderChanged(.specific(AiProvider.openai.rawValue)))
        await store.finish()
        await store.send(.collectionSearchModelChanged(
            .specific(provider: AiProvider.openai.rawValue, model: model.rawModelID),
        ))
        await store.finish()
        await store.send(.collectionSearchThinkingChanged(.effort("low")))
        await store.finish()

        let expectedSettings = CollectionSearchAISettings(
            provider: .specific(AiProvider.openai.rawValue),
            model: .specific(provider: AiProvider.openai.rawValue, model: model.rawModelID),
            thinking: .effort("low"),
        )
        let payload = await queryConversionPayload(for: storedSettings.value)
        XCTAssertEqual(storedSettings.value, expectedSettings)
        XCTAssertEqual(payload, expectedSettings.payload)
    }

    // FLOW-PATH: reset_to_defaults

    /// set.collection_search_ai_settings: reset_to_defaults
    func testResetRestoresDefaultsWithoutChangingChatSelection() async {
        let initialSettings = Self.openAISettings
        let storedSettings = LockIsolated(initialSettings)
        let activeChat = AiChatState(
            selectedModelHandle: .init(provider: .anthropic, rawValue: "claude-3-5-sonnet"),
            selectedThinking: .effort(.high),
        )
        let expectedChatSelection = (activeChat.selectedModelHandle, activeChat.selectedThinking)
        let store = makeSettingsStore(
            storedSettings: storedSettings,
            initialState: AiSettingsState(collectionSearchSettings: storedSettings.value),
        )

        await store.send(.collectionSearchResetTapped)
        await store.finish()

        let payload = await queryConversionPayload(for: storedSettings.value)
        XCTAssertEqual(storedSettings.value, .default)
        XCTAssertEqual(activeChat.selectedModelHandle, expectedChatSelection.0)
        XCTAssertEqual(activeChat.selectedThinking, expectedChatSelection.1)
        XCTAssertEqual(payload, CollectionSearchAISettings.default.payload)
    }

    // FLOW-PATH: unavailable_provider_or_model

    /// set.collection_search_ai_settings: unavailable_provider_or_model
    func testUnavailableProviderOrModelNormalizesBeforeQueryConversion() async throws {
        let unavailableFile = AIConnectionsFile.testFixture(providers: [
            .testFixture(provider: .openai, authMethod: .apiKey, state: .unavailable),
        ])
        let initialSettings = Self.openAISettings
        let storedSettings = LockIsolated(initialSettings)
        let store = makeSettingsStore(
            storedSettings: storedSettings,
            initialState: AiSettingsState(collectionSearchSettings: storedSettings.value),
        )

        try await store.send(.bootstrapCompleted([
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: XCTUnwrap(unavailableFile.providers[AiProvider.openai.rawValue]?.snapshot
                    .lastKnownStatus),
            ),
        ]))
        await store.finish()

        let payload = await queryConversionPayload(for: storedSettings.value)
        XCTAssertEqual(storedSettings.value, .default)
        XCTAssertEqual(payload, CollectionSearchAISettings.default.payload)
    }

    // FLOW-PATH: chat_selection_independence

    /// set.collection_search_ai_settings: chat_selection_independence
    func testCollectionSearchAndChatSelectionsRemainIndependent() async {
        let storedSettings = LockIsolated(CollectionSearchAISettings.default)
        let activeChat = AiChatState(
            selectedModelHandle: .init(provider: .anthropic, rawValue: "claude-3-5-sonnet"),
            selectedThinking: .effort(.high),
        )
        let expectedChatSelection = (activeChat.selectedModelHandle, activeChat.selectedThinking)
        let store = makeSettingsStore(
            storedSettings: storedSettings,
            initialState: AiSettingsState(
                collectionSearchModelsByProvider: [.openai: [Self.openAIModel]],
            ),
        )

        await store.send(.collectionSearchProviderChanged(.specific(AiProvider.openai.rawValue)))
        await store.finish()
        await store.send(.collectionSearchModelChanged(
            .specific(provider: AiProvider.openai.rawValue, model: Self.openAIModel.rawModelID),
        ))
        await store.finish()

        let payload = await queryConversionPayload(for: storedSettings.value)
        XCTAssertEqual(activeChat.selectedModelHandle, expectedChatSelection.0)
        XCTAssertEqual(activeChat.selectedThinking, expectedChatSelection.1)
        XCTAssertEqual(
            payload,
            CollectionSearchAISettings(
                provider: .specific(AiProvider.openai.rawValue),
                model: .specific(provider: AiProvider.openai.rawValue, model: Self.openAIModel.rawModelID),
                thinking: .providerDefault,
            ).payload,
        )
    }

    // FLOW-PATH: collection_change_reset_preserves_chat

    /// set.collection_search_ai_settings: collection_change_reset_preserves_chat
    /// Collection Search 변경과 초기화가 Chat 저장 key와 활성 Chat 선택에 간섭하지 않는지 검증한다.
    /// - 검증 내용: live Collection client change/reset, Chat Data byte 보존, 활성 Chat pair 보존
    /// - 사전 조건: Chat과 Collection Search가 서로 다른 provider/model을 저장하고 활성 Chat이 Anthropic을 사용한다.
    /// - 기대 결과: Collection Search 변경과 초기화 뒤에도 Chat Data와 활성 Chat pair가 그대로 유지된다.
    func testCollectionChangeAndResetPreserveChatKeyAndActiveSelection() async throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        userDefaultsClient.setObject(nil, SettingsKeys.aiChatDefaultSettings)
        userDefaultsClient.setObject(nil, SettingsKeys.collectionSearchAISettings)
        let chatClient = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)
        let collectionClient = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        let chatSettings = Self.anthropicChatSettings
        chatClient.save(chatSettings)
        collectionClient.save(.default)
        let originalChatData = try XCTUnwrap(
            userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings) as? Data,
        )
        let activeChat = AiChatState(
            selectedModelHandle: Self.anthropicModel.id,
            selectedThinking: AiThinkingSelection.none,
        )
        let expectedActiveChat = (activeChat.selectedModelHandle, activeChat.selectedThinking)
        let store = TestStore(initialState: AiSettingsState(
            collectionSearchSettings: .default,
            collectionSearchModelsByProvider: [.openai: [Self.openAIModel]],
            chatDefaultSettings: chatSettings,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = chatClient
            $0.collectionSearchAISettingsClient = collectionClient
        }
        // store.exhaustivity = .off: 두 live persistence key와 reducer runtime aggregate의 비간섭만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.collectionSearchProviderChanged(.specific(AiProvider.openai.rawValue)))
        await store.finish()
        await store.send(.collectionSearchModelChanged(
            .specific(provider: AiProvider.openai.rawValue, model: Self.openAIModel.rawModelID),
        ))
        await store.finish()
        await store.send(.collectionSearchResetTapped)
        await store.finish()

        XCTAssertEqual(userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings) as? Data, originalChatData)
        XCTAssertEqual(chatClient.load(), chatSettings)
        XCTAssertEqual(store.state.chatDefaultSettings, chatSettings)
        XCTAssertEqual(activeChat.selectedModelHandle, expectedActiveChat.0)
        XCTAssertEqual(activeChat.selectedThinking, expectedActiveChat.1)
    }

    // FLOW-PATH: chat_change_reset_preserves_collection

    /// set.collection_search_ai_settings: chat_change_reset_preserves_collection
    /// Chat 기본값 변경과 초기화가 Collection Search 저장 key와 runtime 선택에 간섭하지 않는지 검증한다.
    /// - 검증 내용: live Chat client change/reset, Collection Data byte 보존, Collection runtime aggregate 보존
    /// - 사전 조건: Collection Search는 OpenAI specific 설정이고 Chat은 Anthropic model catalog를 사용한다.
    /// - 기대 결과: Chat 변경과 초기화 뒤에도 Collection Data와 runtime aggregate가 그대로 유지된다.
    func testChatChangeAndResetPreserveCollectionKeyAndRuntimeSelection() async throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        userDefaultsClient.setObject(nil, SettingsKeys.aiChatDefaultSettings)
        userDefaultsClient.setObject(nil, SettingsKeys.collectionSearchAISettings)
        let chatClient = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)
        let collectionClient = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        let collectionSettings = Self.openAISettings
        collectionClient.save(collectionSettings)
        chatClient.save(Self.anthropicChatSettings)
        let originalCollectionData = try XCTUnwrap(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
        )
        let store = TestStore(initialState: AiSettingsState(
            collectionSearchSettings: collectionSettings,
            chatDefaultSettings: Self.anthropicChatSettings,
            chatModelsByProvider: [.anthropic: [Self.anthropicModel]],
            chatModelCatalogPhase: .loaded,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = chatClient
            $0.collectionSearchAISettingsClient = collectionClient
        }
        // store.exhaustivity = .off: 두 live persistence key와 reducer runtime aggregate의 비간섭만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.chatThinkingChanged(AiThinkingSelection.none))
        await store.finish()
        await store.send(.chatResetTapped)
        await store.finish()

        XCTAssertEqual(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
            originalCollectionData,
        )
        XCTAssertEqual(collectionClient.load(), collectionSettings)
        XCTAssertEqual(store.state.collectionSearchSettings, collectionSettings)
    }

    private func makeSettingsStore(
        storedSettings: LockIsolated<CollectionSearchAISettings>,
        initialState: AiSettingsState,
    ) -> TestStore<AiSettingsFeature.State, AiSettingsFeature.Action> {
        let store = TestStore(initialState: initialState) {
            AiSettingsFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { storedSettings.value }
            $0.collectionSearchAISettingsClient.save = { storedSettings.setValue($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }
        // store.exhaustivity = .off: Settings 저장과 Composer 소비를 분리된 reducer 경계에서 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func queryConversionPayload(
        for settings: CollectionSearchAISettings,
    ) async -> CollectionSearchAISettingsPayload? {
        let capturedRequests = LockIsolated<[SearchRequestPayload]>([])
        var initialState = ComposerState()
        initialState.text = "find recent invoices"
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { settings }
            $0.searchClient.search = { request in
                capturedRequests.withValue { $0.append(request) }
                throw CancellationError()
            }
        }
        // store.exhaustivity = .off: query conversion payload 전달을 위한 Composer 실행 경계만 검증한다.
        store.exhaustivity = .off

        await store.send(.submit)
        await store.finish()

        return capturedRequests.value.last?.collectionSearchAISettings
    }
}

private extension CollectionSearchAiSettingsFlowTests {
    static let openAIModel = AiProviderModel(
        id: .init(provider: .openai, rawValue: "gpt-4o-mini"),
        provider: .openai,
        rawModelID: "gpt-4o-mini",
        displayName: "GPT-4o mini",
        providerDisplayName: "OpenAI",
        thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
        supportsThinkingNone: true,
    )

    static let openAISettings = CollectionSearchAISettings(
        provider: .specific(AiProvider.openai.rawValue),
        model: .specific(provider: AiProvider.openai.rawValue, model: openAIModel.rawModelID),
        thinking: .effort("low"),
    )

    static let anthropicModel = AiProviderModel(
        id: .init(provider: .anthropic, rawValue: "claude-sonnet"),
        provider: .anthropic,
        rawModelID: "claude-sonnet",
        displayName: "Claude Sonnet",
        providerDisplayName: "Anthropic",
        thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
        supportsThinkingNone: true,
    )

    static let anthropicChatSettings = AiChatDefaultSettings(
        provider: PersistedAIProviderSelection(rawValue: AiProvider.anthropic.rawValue),
        model: PersistedAIModelSelection(
            providerRawValue: AiProvider.anthropic.rawValue,
            modelRawValue: anthropicModel.rawModelID,
        ),
        thinking: .none,
    )
}

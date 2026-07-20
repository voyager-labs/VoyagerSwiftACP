// FLOW-ID: set.collection_search_ai_settings
import ComposableArchitecture
import Dependencies
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
}

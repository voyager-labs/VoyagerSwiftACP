import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection
import VoyagerShared
@testable import VoyagerPagesSettings
import XCTest

private final class CollectionSearchSettingsSaveSpy: @unchecked Sendable {
    private(set) var saved: [CollectionSearchAISettings] = []

    func save(_ settings: CollectionSearchAISettings) {
        saved.append(settings)
    }
}

@MainActor
final class SET009CollectionSearchAiSettingsTests: XCTestCase {
    // MARK: - SET-009-select_collection_search_ai_provider

    /// SET-009-select_collection_search_ai_provider: bootstrap verification은 연결 provider 모델을 불러오고 stale selection을
    /// auto/default로 정규화한다.
    /// 저장된 collection search AI 선택이 현재 provider 모델 목록과 맞지 않을 때 안전한 기본값으로 회복되는지 검증한다.
    /// - 검증 내용: bootstrap verification completion, model loading, stale model/thinking reset, settings persistence
    /// - 사전 조건: OpenAI는 connected이고 저장된 설정은 더 이상 존재하지 않는 모델과 thinking effort를 가리킨다.
    /// - 기대 결과: provider는 OpenAI로 유지되고 model은 auto, thinking은 providerDefault로 저장된다.
    func testBootstrapVerificationLoadsModelsAndNormalizesStaleSavedSelection() async {
        let saveSpy = CollectionSearchSettingsSaveSpy()
        let settings = Self.staleOpenAISettings
        let model = Self.openAIModel
        let store = TestStore(initialState: AiSettingsState(
            didBootstrap: true,
            bootstrapPhase: .loading,
            collectionSearchSettings: settings,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiConnectionsFileClient.save = { .success($0) }
            $0.aiConnectionsFileClient.deleteCredential = { _ in .success(.empty()) }
            $0.aiProviderModelListClient.loadModels = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return [model]
            }
            $0.collectionSearchAISettingsClient.load = { settings }
            $0.collectionSearchAISettingsClient.save = { saveSpy.save($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }

        await store.send(.bootstrapVerificationCompleted([
            AIProviderBootstrapResult(provider: .openai, connectionState: .connected),
        ])) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .connected
        }
        await store.receive(.collectionSearchModelsLoaded(
            modelsByProvider: [.openai: [model]],
            errorMessage: nil,
        )) { state in
            state.collectionSearchModelsByProvider = [.openai: [model]]
            state.collectionSearchSettings.provider = .specific(AiProvider.openai.rawValue)
            state.collectionSearchSettings.model = .auto
            state.collectionSearchSettings.thinking = .providerDefault
        }

        XCTAssertEqual(saveSpy.saved, [
            CollectionSearchAISettings(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ])
    }

    /// SET-009-select_collection_search_ai_provider: provider 변경은 model auto와 provider default thinking을 함께 저장한다.
    /// 사용자가 collection search provider를 선택할 때 이전 모델/thinking 선택이 새 provider에 누수되지 않는지 검증한다.
    /// - 검증 내용: provider changed action, auto model reset, providerDefault thinking reset, settings persistence
    /// - 사전 조건: 기본 AI settings state에서 OpenAI provider를 선택한다.
    /// - 기대 결과: OpenAI provider와 auto/providerDefault 조합이 저장된다.
    func testProviderChangePersistsAutoModelAndDefaultThinking() async {
        let saveSpy = CollectionSearchSettingsSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { .default }
            $0.collectionSearchAISettingsClient.save = { saveSpy.save($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }

        await store.send(.collectionSearchProviderChanged(.specific(AiProvider.openai.rawValue))) { state in
            state.collectionSearchSettings.provider = .specific(AiProvider.openai.rawValue)
            state.collectionSearchSettings.model = .auto
            state.collectionSearchSettings.thinking = .providerDefault
        }

        XCTAssertEqual(saveSpy.saved, [
            CollectionSearchAISettings(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ])
    }

    /// SET-009-select_collection_search_ai_provider: provider dropdown은 connected provider만 노출한다.
    /// 연결 실패나 미검증 provider가 collection search provider 후보로 표시되지 않는지 검증한다.
    /// - 검증 내용: connectedProviderDescriptors filtering, hasConnectedProviders flag
    /// - 사전 조건: ChatGPT Codex만 connected이고 OpenAI/Anthropic은 미연결 상태다.
    /// - 기대 결과: dropdown 후보는 ChatGPT Codex 하나뿐이다.
    func testProviderDropdownOnlyIncludesConnectedProviders() {
        let state = AiSettingsState(rows: [
            AiConnectionRowState(provider: .chatgptCodex, connectionState: .connected),
            AiConnectionRowState(provider: .openai, connectionState: .notVerified),
            AiConnectionRowState(provider: .anthropic, connectionState: .connectionFailed),
        ])

        XCTAssertTrue(state.hasConnectedProviders)
        XCTAssertEqual(
            state.connectedProviderDescriptors.map(\.provider),
            [.chatgptCodex],
        )
    }

    /// SET-009-select_collection_search_ai_provider: connected provider가 없으면 dropdown 후보가 비어 있다.
    /// collection search AI 설정이 연결되지 않은 provider를 선택지로 만들지 않는지 검증한다.
    /// - 검증 내용: no connected providers, empty descriptors, hasConnectedProviders false
    /// - 사전 조건: 모든 provider가 notVerified/connectionFailed/disconnected 상태다.
    /// - 기대 결과: connected provider 후보가 없다.
    func testProviderDropdownHasNoOptionsWithoutConnectedProviders() {
        let state = AiSettingsState(rows: [
            AiConnectionRowState(provider: .chatgptCodex, connectionState: .notVerified),
            AiConnectionRowState(provider: .openai, connectionState: .connectionFailed),
            AiConnectionRowState(provider: .anthropic, connectionState: .disconnected),
        ])

        XCTAssertFalse(state.hasConnectedProviders)
        XCTAssertTrue(state.connectedProviderDescriptors.isEmpty)
    }

    /// SET-009-select_collection_search_ai_provider: bootstrap은 disconnected provider 설정을 default로 reset한다.
    /// 저장된 collection search provider가 현재 연결되지 않았다면 잘못된 검색 설정을 유지하지 않는지 검증한다.
    /// - 검증 내용: bootstrap completed, disconnected provider detection, settings reset persistence
    /// - 사전 조건: 저장된 설정은 OpenAI specific model/thinking이고 bootstrap 결과 OpenAI는 disconnected다.
    /// - 기대 결과: collectionSearchSettings가 default로 초기화되고 저장된다.
    func testBootstrapResetsDisconnectedCollectionSearchProvider() async {
        let saveSpy = CollectionSearchSettingsSaveSpy()
        let initialState = AiSettingsState(
            collectionSearchSettings: CollectionSearchAISettings(
                provider: .specific(AiProvider.openai.rawValue),
                model: .specific(provider: AiProvider.openai.rawValue, model: "gpt-4o-mini"),
                thinking: .effort("high"),
            ),
        )
        let store = TestStore(initialState: initialState) {
            AiSettingsFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { .default }
            $0.collectionSearchAISettingsClient.save = { saveSpy.save($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }

        await store.send(.bootstrapCompleted([
            AIProviderBootstrapResult(provider: .chatgptCodex, connectionState: .notVerified),
            AIProviderBootstrapResult(provider: .openai, connectionState: .disconnected),
            AIProviderBootstrapResult(provider: .anthropic, connectionState: .notVerified),
        ])) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.collectionSearchSettings = .default
        }

        XCTAssertEqual(saveSpy.saved, [.default])
    }

    /// SET-009-select_collection_search_ai_provider: checkingStatus provider는 bootstrap 중 즉시 reset하지 않는다.
    /// verification이 끝나기 전 임시 checking 상태를 disconnected로 오판하지 않는지 검증한다.
    /// - 검증 내용: bootstrap completed checkingStatus, settings preservation, no save
    /// - 사전 조건: 저장된 설정은 OpenAI이고 bootstrap 결과 OpenAI는 checkingStatus다.
    /// - 기대 결과: 저장된 설정은 유지되고 추가 저장은 발생하지 않는다.
    func testBootstrapKeepsCollectionSearchProviderWhileCheckingStatus() async {
        let saveSpy = CollectionSearchSettingsSaveSpy()
        let settings = CollectionSearchAISettings(
            provider: .specific(AiProvider.openai.rawValue),
            model: .auto,
            thinking: .providerDefault,
        )
        let store = TestStore(initialState: AiSettingsState(collectionSearchSettings: settings)) {
            AiSettingsFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { .default }
            $0.collectionSearchAISettingsClient.save = { saveSpy.save($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }

        await store.send(.bootstrapCompleted([
            AIProviderBootstrapResult(provider: .chatgptCodex, connectionState: .notVerified),
            AIProviderBootstrapResult(provider: .openai, connectionState: .checkingStatus),
            AIProviderBootstrapResult(provider: .anthropic, connectionState: .notVerified),
        ])) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
        }

        XCTAssertTrue(saveSpy.saved.isEmpty)
    }

    /// SET-009-select_collection_search_ai_provider: model load 후 누락된 specific model은 auto/default thinking으로 reset된다.
    /// provider는 유효하지만 저장된 model id가 현재 모델 목록에 없을 때 안전한 기본 선택으로 돌아가는지 검증한다.
    /// - 검증 내용: collectionSearchModelsLoaded, missing specific model detection, settings persistence
    /// - 사전 조건: OpenAI settings가 존재하지 않는 모델과 high thinking effort를 저장하고 있다.
    /// - 기대 결과: model은 auto, thinking은 providerDefault로 저장된다.
    func testLoadedModelsResetMissingSelectionAndPersist() async {
        let saveSpy = CollectionSearchSettingsSaveSpy()
        let initialState = AiSettingsState(
            collectionSearchSettings: CollectionSearchAISettings(
                provider: .specific(AiProvider.openai.rawValue),
                model: .specific(provider: AiProvider.openai.rawValue, model: "gpt-4o-mini-search"),
                thinking: .effort("high"),
            ),
        )
        let model = AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o-mini"),
            provider: .openai,
            rawModelID: "gpt-4o-mini",
            displayName: "GPT-4o mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
            supportsThinkingNone: true,
        )
        let store = TestStore(initialState: initialState) {
            AiSettingsFeature()
        } withDependencies: {
            $0.collectionSearchAISettingsClient.load = { .default }
            $0.collectionSearchAISettingsClient.save = { saveSpy.save($0) }
            $0.collectionSearchAISettingsClient.reset = {}
        }

        await store.send(.collectionSearchModelsLoaded(
            modelsByProvider: [.openai: [model]],
            errorMessage: nil,
        )) { state in
            state.collectionSearchModelsByProvider = [.openai: [model]]
            state.collectionSearchSettings.provider = .specific(AiProvider.openai.rawValue)
            state.collectionSearchSettings.model = .auto
            state.collectionSearchSettings.thinking = .providerDefault
        }

        XCTAssertEqual(saveSpy.saved.count, 1)
        XCTAssertEqual(saveSpy.saved.first?.model, .auto)
        XCTAssertEqual(saveSpy.saved.first?.thinking, .providerDefault)
    }

    // MARK: - SET-009-show_collection_search_ai_settings_section

    /// SET-009-show_collection_search_ai_settings_section: 저장된 collection search AI 설정이 없으면 기본값을 표시한다.
    /// 설정 화면이 최초 진입 시 빈 저장소를 안전하게 기본 provider/model/thinking 선택으로 해석하는지 검증한다.
    /// - 검증 내용: live collectionSearchAISettingsClient load, missing persisted data, default selection
    /// - 사전 조건: collection search AI settings key가 UserDefaults에 존재하지 않는다.
    /// - 기대 결과: provider/model/thinking이 모두 기본 선택으로 로드된다.
    func testLiveSettingsClientLoadReturnsDefaultWhenMissing() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)

        XCTAssertEqual(client.load(), .default)
    }

    /// SET-009-show_collection_search_ai_settings_section: 손상된 collection search AI 설정은 기본값으로 복구된다.
    /// 설정 화면이 decode할 수 없는 저장값 때문에 중단되지 않고 안전한 기본 선택을 표시하는지 검증한다.
    /// - 검증 내용: live collectionSearchAISettingsClient corrupt payload fallback, default selection
    /// - 사전 조건: collection search AI settings key에 Codable payload가 아닌 bytes가 저장되어 있다.
    /// - 기대 결과: 저장값은 그대로 남아도 화면 입력값은 기본 선택으로 로드된다.
    func testLiveSettingsClientLoadReturnsDefaultWhenDataIsCorrupt() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        userDefaultsClient.setObject(Data([0x00, 0x01, 0x02]), SettingsKeys.collectionSearchAISettings)

        XCTAssertEqual(client.load(), .default)
        XCTAssertNotNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)
    }

    // MARK: - SET-009-select_collection_search_ai_provider

    /// SET-009-select_collection_search_ai_provider: 선택한 provider/model/thinking 설정은 저장 후 다시 로드된다.
    /// collection search AI 설정 변경이 persisted settings payload로 round-trip 되는지 검증한다.
    /// - 검증 내용: live collectionSearchAISettingsClient save/load round-trip, provider/model/thinking persistence
    /// - 사전 조건: OpenAI provider, specific model, low thinking effort 설정을 저장한다.
    /// - 기대 결과: load 결과가 저장한 collection search AI 설정과 동일하다.
    func testLiveSettingsClientSaveAndLoadRoundTripPersistsSelection() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        let settings = CollectionSearchAISettings(
            provider: .specific("openai"),
            model: .specific(provider: "openai", model: "gpt-4o-mini"),
            thinking: .effort("low"),
        )

        client.save(settings)

        XCTAssertEqual(client.load(), settings)
    }

    // MARK: - SET-009-reset_collection_search_ai_settings

    /// SET-009-reset_collection_search_ai_settings: reset은 저장된 collection search AI 설정을 제거한다.
    /// 사용자가 collection search AI 설정을 초기화하면 persisted payload가 제거되고 기본값으로 돌아가는지 검증한다.
    /// - 검증 내용: live collectionSearchAISettingsClient reset, persisted key removal, default fallback
    /// - 사전 조건: Anthropic provider와 specific model 설정이 저장되어 있다.
    /// - 기대 결과: UserDefaults key가 제거되고 load 결과는 기본값이다.
    func testLiveSettingsClientResetRemovesStoredValue() {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionSearchAISettingsClient.live(userDefaultsClient: userDefaultsClient)
        client.save(
            CollectionSearchAISettings(
                provider: .specific("anthropic"),
                model: .specific(provider: "anthropic", model: "claude-3-5-sonnet"),
                thinking: .providerDefault,
            ),
        )

        XCTAssertNotNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)

        client.reset()

        XCTAssertNil(userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data)
        XCTAssertEqual(client.load(), .default)
    }

}

private extension SET009CollectionSearchAiSettingsTests {
    static var staleOpenAISettings: CollectionSearchAISettings {
        CollectionSearchAISettings(
            provider: .specific(AiProvider.openai.rawValue),
            model: .specific(provider: AiProvider.openai.rawValue, model: "old-model"),
            thinking: .effort("high"),
        )
    }

    static var openAIModel: AiProviderModel {
        AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o-mini"),
            provider: .openai,
            rawModelID: "gpt-4o-mini",
            displayName: "GPT-4o mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .medium, .high], defaultValue: .medium),
            supportsThinkingNone: true,
        )
    }
}

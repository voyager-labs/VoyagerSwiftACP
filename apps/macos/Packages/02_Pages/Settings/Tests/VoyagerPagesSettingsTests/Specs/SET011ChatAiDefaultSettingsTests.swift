import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

private final class ChatDefaultSettingsSpy: @unchecked Sendable {
    let loaded: AiChatDefaultSettings
    private(set) var saved: [AiChatDefaultSettings] = []
    private(set) var resetCount = 0

    init(loaded: AiChatDefaultSettings = .default) {
        self.loaded = loaded
    }

    func save(_ settings: AiChatDefaultSettings) {
        saved.append(settings)
    }

    func reset() {
        resetCount += 1
    }
}

private final class CollectionSettingsIsolationSpy: @unchecked Sendable {
    private(set) var saved: [CollectionSearchAISettings] = []
    private(set) var resetCount = 0

    func save(_ settings: CollectionSearchAISettings) {
        saved.append(settings)
    }

    func reset() {
        resetCount += 1
    }
}

private enum ChatSettingsTestError: Error { case failed }

private extension AiProviderConnectionResult {
    static func connectSuccess(
        provider: AiProvider,
        file: AIConnectionsFile,
    ) -> Self {
        AiProviderConnectionResult(
            provider: provider,
            state: .connected,
            reason: .none,
            updatedFile: file,
        )
    }
}

private actor ChatModelRequestController {
    let latestModels: [AiProviderModel]
    private var requestCount = 0
    private var firstRequestStarted = false
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?

    init(latestModels: [AiProviderModel]) {
        self.latestModels = latestModels
    }

    func load() async throws -> [AiProviderModel] {
        requestCount += 1
        if requestCount == 1 {
            firstRequestStarted = true
            firstRequestContinuation?.resume()
            firstRequestContinuation = nil
            try await Task.sleep(for: .seconds(60))
        }
        return latestModels
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func currentRequestCount() -> Int {
        requestCount
    }
}

@MainActor
final class SET011ChatAiDefaultSettingsTests: XCTestCase {
    // MARK: - SET-011-show_default_chat_ai_settings

    /// SET-011-show_default_chat_ai_settings: 저장된 Chat 기본값이 없으면 no-selection을 반환한다.
    /// Chat 기본 설정을 저장하지 않은 최초 상태가 Collection Search의 Auto 선택과 분리되는지 검증한다.
    /// - 검증 내용: live AiChatDefaultSettingsClient missing payload fallback
    /// - 사전 조건: Chat key는 없고 Collection Search key에는 별도 payload가 저장되어 있다.
    /// - 기대 결과: Chat은 provider/model 미선택과 provider default Thinking을 반환한다.
    func testLiveClientLoadReturnsNoSelectionWhenMissing() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let collectionData = try JSONEncoder().encode(CollectionSearchAISettings.default)
        userDefaultsClient.setObject(collectionData, SettingsKeys.collectionSearchAISettings)
        let client = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)

        XCTAssertEqual(client.load(), .default)
        XCTAssertNil(client.load().provider)
        XCTAssertNil(client.load().model)
        XCTAssertEqual(client.load().thinking, .providerDefault)
        XCTAssertEqual(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
            collectionData,
        )
    }

    /// SET-011-show_default_chat_ai_settings: 손상된 Chat payload는 no-selection으로 복구된다.
    /// decode할 수 없는 Chat 저장값이 Collection Search 설정으로 fallback하지 않는지 검증한다.
    /// - 검증 내용: corrupt Data fallback, corrupt payload preservation, Collection key independence
    /// - 사전 조건: Chat key에는 invalid JSON bytes, Collection key에는 유효한 specific 설정이 저장되어 있다.
    /// - 기대 결과: Chat은 no-selection이고 두 key의 원본 bytes는 변경되지 않는다.
    func testLiveClientLoadReturnsNoSelectionWhenDataIsCorrupt() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let corruptData = Data([0x00, 0x01, 0x02])
        let collectionData = try JSONEncoder().encode(CollectionSearchAISettings(
            provider: .specific("anthropic"),
            model: .specific(provider: "anthropic", model: "claude-3-5-sonnet"),
            thinking: .none,
        ))
        userDefaultsClient.setObject(corruptData, SettingsKeys.aiChatDefaultSettings)
        userDefaultsClient.setObject(collectionData, SettingsKeys.collectionSearchAISettings)
        let client = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)

        XCTAssertEqual(client.load(), .default)
        XCTAssertEqual(userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings) as? Data, corruptData)
        XCTAssertEqual(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
            collectionData,
        )
    }

    // MARK: - SET-011-select_default_chat_ai_provider

    /// SET-011-select_default_chat_ai_provider: Chat 기본 선택은 독립 key에서 저장 후 다시 로드된다.
    /// OpenAI provider/model/thinking 선택의 persistence round-trip과 Collection bytes 불변을 검증한다.
    /// - 검증 내용: live client save/load, 새 client instance load, independent UserDefaults keys
    /// - 사전 조건: Collection key bytes를 먼저 저장하고 OpenAI/gpt-4o/high Chat 기본값을 저장한다.
    /// - 기대 결과: 새 client가 같은 Chat aggregate를 반환하고 Collection bytes는 byte-for-byte 동일하다.
    func testLiveClientSaveAndLoadRoundTripPreservesCollectionBytes() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let collectionData = try JSONEncoder().encode(CollectionSearchAISettings(
            provider: .specific("anthropic"),
            model: .specific(provider: "anthropic", model: "claude-3-5-sonnet"),
            thinking: .tokenBudget(4096),
        ))
        userDefaultsClient.setObject(collectionData, SettingsKeys.collectionSearchAISettings)
        let settings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: "openai"),
            model: PersistedAIModelSelection(providerRawValue: "openai", modelRawValue: "gpt-4o"),
            thinking: .effort("high"),
        )
        AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient).save(settings)

        let reloadedClient = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)

        XCTAssertEqual(reloadedClient.load(), settings)
        XCTAssertEqual(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
            collectionData,
        )
    }

    /// SET-011-select_default_chat_ai_provider: catalog에 없는 raw provider/model 값도 그대로 decode한다.
    /// 연결이 끊긴 provider가 다시 연결될 수 있으므로 stale intent를 저장 계층에서 정규화하지 않는지 검증한다.
    /// - 검증 내용: unknown raw provider/model and Thinking Codable preservation
    /// - 사전 조건: future-provider/future-model/xhigh 값을 JSON으로 encode해 Chat key에 저장한다.
    /// - 기대 결과: load 결과가 모든 raw 값을 손실 없이 반환한다.
    func testLiveClientLoadPreservesStaleRawValues() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let staleSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: "future-provider"),
            model: PersistedAIModelSelection(
                providerRawValue: "future-provider",
                modelRawValue: "future-model",
            ),
            thinking: .effort("xhigh"),
        )
        try userDefaultsClient.setObject(
            JSONEncoder().encode(staleSettings),
            SettingsKeys.aiChatDefaultSettings,
        )

        XCTAssertEqual(
            AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient).load(),
            staleSettings,
        )
    }

    // MARK: - SET-011-reset_default_chat_ai_settings

    /// SET-011-reset_default_chat_ai_settings: reset은 Chat key만 제거한다.
    /// Chat 기본값 초기화가 Collection Search 저장 payload를 변경하거나 제거하지 않는지 검증한다.
    /// - 검증 내용: Chat reset key removal, no-selection fallback, Collection bytes preservation
    /// - 사전 조건: Chat과 Collection Search key 모두 서로 다른 valid Data를 가진다.
    /// - 기대 결과: Chat key만 제거되고 Collection bytes는 byte-for-byte 유지된다.
    func testLiveClientResetRemovesOnlyChatKey() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let collectionData = try JSONEncoder().encode(CollectionSearchAISettings(
            provider: .specific("openai"),
            model: .specific(provider: "openai", model: "gpt-4o-mini"),
            thinking: .providerDefault,
        ))
        userDefaultsClient.setObject(collectionData, SettingsKeys.collectionSearchAISettings)
        let client = AiChatDefaultSettingsClient.live(userDefaultsClient: userDefaultsClient)
        client.save(AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: "anthropic"),
            model: PersistedAIModelSelection(
                providerRawValue: "anthropic",
                modelRawValue: "claude-3-5-sonnet",
            ),
            thinking: .none,
        ))

        client.reset()

        XCTAssertNil(userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings))
        XCTAssertEqual(client.load(), .default)
        XCTAssertEqual(
            userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data,
            collectionData,
        )
    }

    // MARK: - SET-011-show_default_chat_ai_settings

    /// SET-011-show_default_chat_ai_settings: onAppear는 stale Chat raw 값을 정규화 없이 로드한다.
    /// 설정 화면 진입 시 unavailable provider/model intent가 Collection Search와 독립적으로 보존되는지 검증한다.
    /// - 검증 내용: `.onAppear`, Chat client load, bootstrap failure, no implicit Chat save
    /// - 사전 조건: Chat client는 future provider/model을, Collection client는 OpenAI aggregate를 반환한다.
    /// - 기대 결과: stale Chat aggregate가 그대로 state에 남고 두 설정 client 모두 저장되지 않는다.
    func testOnAppearLoadsStaleChatSettingsWithoutSavingOrChangingCollection() async {
        let staleSettings = Self.staleChatSettings
        let collectionSettings = Self.collectionSettings
        let chatSpy = ChatDefaultSettingsSpy(loaded: staleSettings)
        let collectionSpy = CollectionSettingsIsolationSpy()
        let store = TestStore(initialState: AiSettingsState(
            collectionSearchSettings: collectionSettings,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.collectionSearchAISettingsClient = CollectionSearchAISettingsClient(
                load: { collectionSettings },
                save: { collectionSpy.save($0) },
                reset: { collectionSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = { throw ChatSettingsTestError.failed }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
            state.chatDefaultSettings = staleSettings
        }
        await store.receive(.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.chatDefaultSettings, staleSettings)
        XCTAssertEqual(store.state.collectionSearchSettings, collectionSettings)
        XCTAssertTrue(store.state.chatSelectedProviderIsUnavailable)
        XCTAssertTrue(store.state.chatSelectedModelIsUnavailable)
        XCTAssertTrue(chatSpy.saved.isEmpty)
        XCTAssertTrue(collectionSpy.saved.isEmpty)
    }

    // MARK: - SET-011-select_default_chat_ai_provider

    /// SET-011-select_default_chat_ai_provider: connected provider/model/thinking 선택은 단계별로 autosave된다.
    /// Chat model catalog가 Collection Search 지원 필터 없이 전체 모델을 노출하면서 provider-only 상태도 저장하는지 검증한다.
    /// - 검증 내용: provider change, full catalog load, model pair save, thinking persisted conversion
    /// - 사전 조건: OpenAI가 connected이고 catalog에는 Collection Search 비지원 legacy 모델이 포함된다.
    /// - 기대 결과: provider-only, provider/model, provider/model/high Thinking aggregate가 순서대로 저장된다.
    func testConnectedProviderModelAndThinkingSelectionsAutosaveFullCatalog() async {
        let chatSpy = ChatDefaultSettingsSpy()
        let models = [Self.legacyChatModel, Self.openAIModel]
        let store = Self.connectedOpenAIAutosaveStore(chatSpy: chatSpy, models: models)

        let providerSelection = PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue)
        let requestID = UUID(0)
        await store.send(.chatProviderChanged(providerSelection)) { state in
            state.chatDefaultSettings = AiChatDefaultSettings(
                provider: providerSelection,
                model: nil,
                thinking: .providerDefault,
            )
            state.chatModelCatalogPhase = .loading
            state.chatModelRequestID = requestID
        }
        await store.receive(.chatModelsLoaded(provider: .openai, requestID: requestID, models: models)) { state in
            state.chatModelsByProvider[.openai] = models
            state.chatModelCatalogPhase = .loaded
            state.chatModelRequestID = nil
        }

        let modelSelection = PersistedAIModelSelection(
            providerRawValue: AiProvider.openai.rawValue,
            modelRawValue: Self.legacyChatModel.rawModelID,
        )
        await store.send(.chatModelChanged(modelSelection)) { state in
            state.chatDefaultSettings.model = modelSelection
        }
        await store.send(.chatThinkingChanged(.effort(.high))) { state in
            state.chatDefaultSettings.thinking = .effort(AiThinkingEffort.high.rawValue)
        }
        await store.finish()

        XCTAssertEqual(store.state.chatModelsByProvider[.openai], models)
        XCTAssertFalse(CollectionSearchAISelectionPolicy.supportsQueryConversion(Self.legacyChatModel))
        XCTAssertEqual(chatSpy.saved, [
            AiChatDefaultSettings(provider: providerSelection, model: nil, thinking: .providerDefault),
            AiChatDefaultSettings(
                provider: providerSelection,
                model: modelSelection,
                thinking: .providerDefault,
            ),
            AiChatDefaultSettings(
                provider: providerSelection,
                model: modelSelection,
                thinking: .effort(AiThinkingEffort.high.rawValue),
            ),
        ])
    }

    // MARK: - SET-011-select_default_chat_ai_model

    /// SET-011-select_default_chat_ai_model: model 변경은 호환되지 않는 Thinking을 provider default로 정규화한다.
    /// 이전 model의 token budget이 새 effort model에 누수되지 않고 저장 직전에 정책으로 정리되는지 검증한다.
    /// - 검증 내용: `.chatModelChanged`, `AiThinkingSelectionPolicy.normalize`, persisted aggregate save
    /// - 사전 조건: OpenAI provider-only state에 token budget Thinking과 effort model catalog가 있다.
    /// - 기대 결과: provider/model pair와 providerDefault Thinking이 저장된다.
    func testModelChangeNormalizesIncompatibleThinkingBeforeAutosave() async {
        let chatSpy = ChatDefaultSettingsSpy()
        let providerSelection = PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue)
        var chatSettings = AiChatDefaultSettings(
            provider: providerSelection,
            model: nil,
            thinking: .tokenBudget(4096),
        )
        let store = TestStore(initialState: AiSettingsState(
            chatDefaultSettings: chatSettings,
            chatModelsByProvider: [.openai: [Self.openAIModel]],
            chatModelCatalogPhase: .loaded,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
        }
        let modelSelection = PersistedAIModelSelection(
            providerRawValue: AiProvider.openai.rawValue,
            modelRawValue: Self.openAIModel.rawModelID,
        )
        chatSettings.model = modelSelection
        chatSettings.thinking = .providerDefault

        await store.send(.chatModelChanged(modelSelection)) { state in
            state.chatDefaultSettings = chatSettings
        }
        await store.finish()

        XCTAssertEqual(chatSpy.saved, [chatSettings])
    }

    /// SET-011-select_default_chat_ai_model: bootstrap은 disconnected stale provider/model을 보존한다.
    /// 다시 연결될 수 있는 Chat intent를 Collection Search처럼 default로 reset하지 않는지 검증한다.
    /// - 검증 내용: bootstrap completion, unavailable derivation, no Chat autosave
    /// - 사전 조건: future provider/model이 저장되어 있고 모든 known provider는 disconnected 상태다.
    /// - 기대 결과: stale aggregate가 그대로 남고 unavailable 상태이며 Chat save는 호출되지 않는다.
    func testBootstrapPreservesDisconnectedStaleProviderAndModel() async {
        let chatSpy = ChatDefaultSettingsSpy(loaded: Self.staleChatSettings)
        let store = TestStore(initialState: AiSettingsState(
            chatDefaultSettings: Self.staleChatSettings,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
        }

        await store.send(.bootstrapCompleted([
            AIProviderBootstrapResult(provider: .chatgptCodex, connectionState: .disconnected),
            AIProviderBootstrapResult(provider: .openai, connectionState: .disconnected),
            AIProviderBootstrapResult(provider: .anthropic, connectionState: .disconnected),
        ])) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .disconnected
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.connectionState = .disconnected
        }

        XCTAssertEqual(store.state.chatDefaultSettings, Self.staleChatSettings)
        XCTAssertTrue(store.state.chatSelectedProviderIsUnavailable)
        XCTAssertTrue(store.state.chatSelectedModelIsUnavailable)
        XCTAssertTrue(chatSpy.saved.isEmpty)
    }

    /// SET-011-select_default_chat_ai_model: model catalog load는 stale model/thinking을 덮어쓰지 않는다.
    /// connected provider의 최신 catalog에 저장 model이 없어도 runtime projection 전까지 raw intent를 유지하는지 검증한다.
    /// - 검증 내용: bootstrap verification, full Chat catalog load, no normalization/save on load
    /// - 사전 조건: OpenAI는 connected이고 Chat aggregate는 old-model/xhigh를 저장했지만 catalog에는 GPT-4o만 있다.
    /// - 기대 결과: catalog는 loaded이고 model은 unavailable로 표시되며 aggregate와 persistence는 변하지 않는다.
    func testModelCatalogLoadPreservesStaleModelAndThinkingWithoutAutosave() async {
        let staleSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: AiProvider.openai.rawValue,
                modelRawValue: "old-model",
            ),
            thinking: .effort(AiThinkingEffort.xhigh.rawValue),
        )
        let chatSpy = ChatDefaultSettingsSpy(loaded: staleSettings)
        let model = Self.openAIModel
        let store = TestStore(initialState: AiSettingsState(
            didBootstrap: true,
            bootstrapPhase: .loading,
            chatDefaultSettings: staleSettings,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = {
                AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderModelListClient.loadModels = { _, _ in [model] }
            $0.uuid = .incrementing
        }
        let requestID = UUID(0)

        await store.send(.bootstrapVerificationCompleted([
            AIProviderBootstrapResult(provider: .openai, connectionState: .connected),
        ])) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .connected
            state.chatModelCatalogPhase = .loading
            state.chatModelRequestID = requestID
        }
        await store.receive(.chatModelsLoaded(
            provider: .openai,
            requestID: requestID,
            models: [model],
        )) { state in
            state.chatModelsByProvider[.openai] = [model]
            state.chatModelCatalogPhase = .loaded
            state.chatModelRequestID = nil
        }

        XCTAssertEqual(store.state.chatDefaultSettings, staleSettings)
        XCTAssertTrue(store.state.chatSelectedModelIsUnavailable)
        XCTAssertTrue(store.state.chatThinkingIsUnavailable)
        XCTAssertTrue(chatSpy.saved.isEmpty)
    }

    /// SET-011-select_default_chat_ai_provider: model picker 상태는 no-provider/loading/failed를 구분한다.
    /// provider 연결 후 catalog 실패가 stale model 자동 선택 없이 명시적인 failure 상태로 끝나는지 검증한다.
    /// - 검증 내용: provider availability, catalog phase transitions, load error state, provider-only persistence
    /// - 사전 조건: 초기 Chat provider는 없고 OpenAI만 connected이며 model client는 실패한다.
    /// - 기대 결과: idle no-provider에서 loading을 거쳐 failed가 되고 model selection은 nil로 유지된다.
    func testModelCatalogStateCoversNoProviderLoadingAndFailure() async {
        let chatSpy = ChatDefaultSettingsSpy()
        let initialState = AiSettingsState(
            didBootstrap: true,
            rows: [AiConnectionRowState(provider: .openai, connectionState: .connected)],
        )
        XCTAssertNil(initialState.chatDefaultSettings.provider)
        XCTAssertEqual(initialState.chatModelCatalogPhase, .idle)
        XCTAssertFalse(initialState.chatSelectedProviderIsUnavailable)

        let store = TestStore(initialState: initialState) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = {
                AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderModelListClient.loadModels = { _, _ in
                throw ChatSettingsTestError.failed
            }
            $0.uuid = .incrementing
        }
        let providerSelection = PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue)
        let requestID = UUID(0)
        await store.send(.chatProviderChanged(providerSelection)) { state in
            state.chatDefaultSettings.provider = providerSelection
            state.chatModelCatalogPhase = .loading
            state.chatModelRequestID = requestID
        }
        await store.receive(.chatModelsFailed(
            provider: .openai,
            requestID: requestID,
            message: "Failed to load chat models for openai.",
        )) { state in
            state.chatModelCatalogPhase = .failed
            state.chatModelRequestID = nil
            state.chatModelLoadError = "Failed to load chat models for openai."
        }
        await store.finish()
        XCTAssertNil(store.state.chatDefaultSettings.model)
        XCTAssertEqual(chatSpy.saved, [
            AiChatDefaultSettings(provider: providerSelection, model: nil, thinking: .providerDefault),
        ])
    }

    // MARK: - SET-011-reset_default_chat_ai_settings

    /// SET-011-reset_default_chat_ai_settings: reducer reset은 Chat aggregate와 Chat client만 변경한다.
    /// Default Chat 초기화가 Collection Search aggregate/client 및 catalog cache에 간섭하지 않는지 검증한다.
    /// - 검증 내용: `.chatResetTapped`, Chat reset effect, Collection non-interference
    /// - 사전 조건: Chat과 Collection Search가 각각 specific aggregate를 가지고 Chat catalog가 loaded 상태다.
    /// - 기대 결과: Chat aggregate만 default가 되고 Chat reset은 1회, Collection save/reset은 0회다.
    func testReducerResetOnlyResetsChatAggregateAndClient() async {
        let chatSpy = ChatDefaultSettingsSpy()
        let collectionSpy = CollectionSettingsIsolationSpy()
        let collectionSettings = Self.collectionSettings
        let chatSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: AiProvider.openai.rawValue,
                modelRawValue: Self.openAIModel.rawModelID,
            ),
            thinking: .effort(AiThinkingEffort.high.rawValue),
        )
        let store = TestStore(initialState: AiSettingsState(
            collectionSearchSettings: collectionSettings,
            chatDefaultSettings: chatSettings,
            chatModelsByProvider: [.openai: [Self.openAIModel]],
            chatModelCatalogPhase: .loaded,
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.collectionSearchAISettingsClient = CollectionSearchAISettingsClient(
                load: { collectionSettings },
                save: { collectionSpy.save($0) },
                reset: { collectionSpy.reset() },
            )
        }
        await store.send(.chatResetTapped) { state in
            state.chatDefaultSettings = .default
        }
        await store.finish()
        XCTAssertEqual(store.state.collectionSearchSettings, collectionSettings)
        XCTAssertEqual(store.state.chatModelsByProvider, [.openai: [Self.openAIModel]])
        XCTAssertEqual(store.state.chatModelCatalogPhase, .loaded)
        XCTAssertEqual(chatSpy.resetCount, 1)
        XCTAssertTrue(chatSpy.saved.isEmpty)
        XCTAssertTrue(collectionSpy.saved.isEmpty)
        XCTAssertEqual(collectionSpy.resetCount, 0)
    }

    /// SET-011-show_default_chat_ai_settings: Default Chat summary/disclosure와 controls가 presentation 계약을 노출한다.
    /// VoiceOver label, no-selection summary, unavailable display와 독립적인 editor 확장 전이를 검증한다.
    /// - 검증 내용: summary/control labels, Not configured, Unavailable, independent expansion transition
    /// - 사전 조건: Default Chat row와 네 control의 presentation helper가 정의되어 있다.
    /// - 기대 결과: 두 editor를 함께 열 수 있고 하나를 닫아도 다른 editor는 열린 상태를 유지한다.
    func testDefaultChatAccessibilityLabelsAreCanonical() {
        XCTAssertEqual(AiSettingsView.defaultChatSummaryAccessibilityLabel, "Default Chat Settings")
        XCTAssertEqual(AiSettingsView.defaultChatProviderAccessibilityLabel, "Default Chat Provider")
        XCTAssertEqual(AiSettingsView.defaultChatModelAccessibilityLabel, "Default Chat Model")
        XCTAssertEqual(AiSettingsView.defaultChatThinkingAccessibilityLabel, "Default Chat Thinking")
        XCTAssertEqual(AiSettingsView.resetChatDefaultsAccessibilityLabel, "Reset Chat Defaults")
        XCTAssertEqual(AiSettingsView.unavailableLabel("future-model"), "future-model (Unavailable)")
        XCTAssertEqual(AiSettingsView.defaultChatSummary(settings: .default), "Not configured")
        let defaultOnly = AiSettingsView.nextEditors([], .defaultChat, true)
        let bothOpen = AiSettingsView.nextEditors(defaultOnly, .collectionSearch, true)
        let collectionOnly = AiSettingsView.nextEditors(bothOpen, .defaultChat, false)
        XCTAssertEqual(defaultOnly, [.defaultChat])
        XCTAssertEqual(bothOpen, [.defaultChat, .collectionSearch])
        XCTAssertEqual(collectionOnly, [.collectionSearch])
    }
}

extension SET011ChatAiDefaultSettingsTests {
    // MARK: - SET-011-select_default_chat_ai_model

    /// SET-011-select_default_chat_ai_model: same-provider stale success는 최신 request catalog를 덮어쓰지 않는다.
    /// provider 문자열이 같아도 이전 generation completion을 request ID로 거부하는지 검증한다.
    /// - 검증 내용: stale `.chatModelsLoaded` provider/request guard
    /// - 사전 조건: OpenAI 최신 request가 loading 중이고 최신 catalog가 state에 있다.
    /// - 기대 결과: 이전 request success 후에도 최신 catalog, loading phase, request ID가 유지된다.
    func testSameProviderStaleSuccessCannotOverwriteLatestRequest() async {
        let staleRequestID = UUID(0)
        let latestRequestID = UUID(1)
        let latestModels = [Self.openAIModel]
        let store = TestStore(initialState: Self.loadingOpenAIState(
            requestID: latestRequestID,
            models: latestModels,
        )) {
            AiSettingsFeature()
        }

        await store.send(.chatModelsLoaded(
            provider: .openai,
            requestID: staleRequestID,
            models: [Self.legacyChatModel],
        ))

        XCTAssertEqual(store.state.chatModelsByProvider[.openai], latestModels)
        XCTAssertEqual(store.state.chatModelCatalogPhase, .loading)
        XCTAssertEqual(store.state.chatModelRequestID, latestRequestID)
        XCTAssertNil(store.state.chatModelLoadError)
    }

    /// SET-011-select_default_chat_ai_model: same-provider stale failure는 최신 request를 failed로 바꾸지 않는다.
    /// 취소 직전 이전 generation이 failure를 보내더라도 최신 generation 상태를 보존하는지 검증한다.
    /// - 검증 내용: stale `.chatModelsFailed` provider/request guard
    /// - 사전 조건: OpenAI 최신 request가 loading 중이고 이전 request failure action이 도착한다.
    /// - 기대 결과: 최신 catalog와 request ID가 유지되고 error와 failed phase는 설정되지 않는다.
    func testSameProviderStaleFailureCannotOverwriteLatestRequest() async {
        let staleRequestID = UUID(0)
        let latestRequestID = UUID(1)
        let latestModels = [Self.openAIModel]
        let store = TestStore(initialState: Self.loadingOpenAIState(
            requestID: latestRequestID,
            models: latestModels,
        )) {
            AiSettingsFeature()
        }

        await store.send(.chatModelsFailed(
            provider: .openai,
            requestID: staleRequestID,
            message: "stale failure",
        ))

        XCTAssertEqual(store.state.chatModelsByProvider[.openai], latestModels)
        XCTAssertEqual(store.state.chatModelCatalogPhase, .loading)
        XCTAssertEqual(store.state.chatModelRequestID, latestRequestID)
        XCTAssertNil(store.state.chatModelLoadError)
    }

    // MARK: - SET-011-select_default_chat_ai_provider

    /// SET-011-select_default_chat_ai_provider: 선택된 provider 재연결은 model catalog를 즉시 새로고침한다.
    /// 같은 Settings 화면에서 OpenAI를 다시 연결한 뒤 stale catalog가 최신 모델로 회복되는지 검증한다.
    /// - 검증 내용: row connectionResponse, fresh request ID, cancellation-safe catalog refresh, Chat persistence 격리
    /// - 사전 조건: OpenAI가 Chat 기본 provider이고 stale model, failed catalog, reconnecting row 상태다.
    /// - 기대 결과: catalog가 UUID(0) loading 후 최신 모델로 loaded되고 Chat 기본 설정은 저장되지 않는다.
    func testReconnectingSelectedProviderRefreshesChatModelCatalogWithoutPersistenceMutation() async {
        let staleSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: AiProvider.openai.rawValue,
                modelRawValue: "old-model",
            ),
            thinking: .providerDefault,
        )
        let updatedFile = AIConnectionsFile.singleProvider(.openai, state: .connected)
        let model = Self.openAIModel
        let chatSpy = ChatDefaultSettingsSpy(loaded: staleSettings)
        let store = Self.reconnectingOpenAIStore(
            staleSettings: staleSettings,
            updatedFile: updatedFile,
            model: model,
            chatSpy: chatSpy,
        )
        let requestID = UUID(0)

        XCTAssertTrue(store.state.chatSelectedProviderIsUnavailable)
        XCTAssertTrue(store.state.chatSelectedModelIsUnavailable)

        await store.send(.row(.element(
            id: .openai,
            action: .connectionResponse(.connectSuccess(provider: .openai, file: updatedFile)),
        ))) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.flowState = .idle
            state.chatModelCatalogPhase = .loading
            state.chatModelRequestID = requestID
            state.chatModelLoadError = nil
        }
        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
        await store.receive(.chatModelsLoaded(
            provider: .openai,
            requestID: requestID,
            models: [model],
        )) { state in
            state.chatModelsByProvider[.openai] = [model]
            state.chatModelCatalogPhase = .loaded
            state.chatModelRequestID = nil
        }
        await store.finish()

        XCTAssertTrue(chatSpy.saved.isEmpty)
        XCTAssertEqual(chatSpy.resetCount, 0)
    }

    /// SET-011-select_default_chat_ai_provider: same-provider 재요청 취소는 failure action을 보내지 않는다.
    /// 첫 model request를 확실히 suspend한 뒤 같은 provider 재선택으로 취소해 effect cancellation 경계를 검증한다.
    /// - 검증 내용: fresh UUID generation, cancelInFlight, CancellationError no-action, latest success acceptance
    /// - 사전 조건: 첫 OpenAI request는 suspend되고 두 번째 OpenAI request는 최신 catalog를 반환한다.
    /// - 기대 결과: UUID(1) success만 수락되고 failed action 없이 loaded로 완료된다.
    func testSameProviderSupersessionCancellationEmitsNoFailure() async {
        let chatSpy = ChatDefaultSettingsSpy()
        let latestModels = [Self.openAIModel]
        let controller = ChatModelRequestController(latestModels: latestModels)
        let store = Self.sameProviderSupersessionStore(chatSpy: chatSpy, controller: controller)
        let providerSelection = PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue)

        await store.send(.chatProviderChanged(providerSelection)) { state in
            state.chatDefaultSettings.provider = providerSelection
            state.chatModelCatalogPhase = .loading
            state.chatModelRequestID = UUID(0)
        }
        await controller.waitUntilFirstRequestStarts()

        await store.send(.chatProviderChanged(providerSelection)) { state in
            state.chatModelRequestID = UUID(1)
        }
        await store.receive(.chatModelsLoaded(
            provider: .openai,
            requestID: UUID(1),
            models: latestModels,
        )) { state in
            state.chatModelsByProvider[.openai] = latestModels
            state.chatModelCatalogPhase = .loaded
            state.chatModelRequestID = nil
        }
        await store.finish()

        let requestCount = await controller.currentRequestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(store.state.chatModelLoadError)
    }
}

private extension SET011ChatAiDefaultSettingsTests {
    static func reconnectingOpenAIStore(
        staleSettings: AiChatDefaultSettings,
        updatedFile: AIConnectionsFile,
        model: AiProviderModel,
        chatSpy: ChatDefaultSettingsSpy,
    ) -> TestStore<AiSettingsState, AiSettingsAction> {
        TestStore(initialState: AiSettingsState(
            didBootstrap: true,
            rows: [
                AiConnectionRowState(
                    provider: .openai,
                    connectionState: .connectInProgress,
                    flowState: .connecting,
                ),
            ],
            chatDefaultSettings: staleSettings,
            chatModelCatalogPhase: .failed,
            chatModelLoadError: "stale failure",
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = { updatedFile }
            $0.aiProviderModelListClient.loadModels = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return [model]
            }
            $0.uuid = .incrementing
        }
    }

    static func connectedOpenAIAutosaveStore(
        chatSpy: ChatDefaultSettingsSpy,
        models: [AiProviderModel],
    ) -> TestStore<AiSettingsState, AiSettingsAction> {
        TestStore(initialState: AiSettingsState(
            didBootstrap: true,
            rows: [AiConnectionRowState(provider: .openai, connectionState: .connected)],
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = {
                AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderModelListClient.loadModels = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return models
            }
            $0.uuid = .incrementing
        }
    }

    static func sameProviderSupersessionStore(
        chatSpy: ChatDefaultSettingsSpy,
        controller: ChatModelRequestController,
    ) -> TestStore<AiSettingsState, AiSettingsAction> {
        TestStore(initialState: AiSettingsState(
            didBootstrap: true,
            rows: [AiConnectionRowState(provider: .openai, connectionState: .connected)],
        )) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiChatDefaultSettingsClient = AiChatDefaultSettingsClient(
                load: { chatSpy.loaded },
                save: { chatSpy.save($0) },
                reset: { chatSpy.reset() },
            )
            $0.aiConnectionsFileClient.load = {
                AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderModelListClient.loadModels = { _, _ in
                try await controller.load()
            }
            $0.uuid = .incrementing
        }
    }

    static func loadingOpenAIState(
        requestID: UUID,
        models: [AiProviderModel],
    ) -> AiSettingsState {
        AiSettingsState(
            chatDefaultSettings: AiChatDefaultSettings(
                provider: PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue),
                model: nil,
                thinking: .providerDefault,
            ),
            chatModelsByProvider: [.openai: models],
            chatModelCatalogPhase: .loading,
            chatModelRequestID: requestID,
        )
    }

    static var collectionSettings: CollectionSearchAISettings {
        CollectionSearchAISettings(
            provider: .specific(AiProvider.openai.rawValue),
            model: .auto,
            thinking: .providerDefault,
        )
    }

    static var staleChatSettings: AiChatDefaultSettings {
        AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: "future-provider"),
            model: PersistedAIModelSelection(
                providerRawValue: "future-provider",
                modelRawValue: "future-model",
            ),
            thinking: .effort("future-effort"),
        )
    }

    static var openAIModel: AiProviderModel {
        AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o"),
            provider: .openai,
            rawModelID: "gpt-4o",
            displayName: "GPT-4o",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: .low),
            supportsThinkingNone: true,
        )
    }

    static var legacyChatModel: AiProviderModel {
        AiProviderModel(
            id: .init(provider: .openai, rawValue: "text-davinci-003"),
            provider: .openai,
            rawModelID: "text-davinci-003",
            displayName: "Text Davinci 003",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: .low),
            supportsThinkingNone: true,
        )
    }
}

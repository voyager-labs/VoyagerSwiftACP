import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

private final class CollectionSearchSettingsSaveSpy: @unchecked Sendable {
    private(set) var saved: [CollectionSearchAISettings] = []

    func save(_ settings: CollectionSearchAISettings) {
        saved.append(settings)
    }
}

@MainActor
final class CollectionSearchAISettingsFeatureTests: XCTestCase {
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

    func testProviderDropdownHasNoOptionsWithoutConnectedProviders() {
        let state = AiSettingsState(rows: [
            AiConnectionRowState(provider: .chatgptCodex, connectionState: .notVerified),
            AiConnectionRowState(provider: .openai, connectionState: .connectionFailed),
            AiConnectionRowState(provider: .anthropic, connectionState: .disconnected),
        ])

        XCTAssertFalse(state.hasConnectedProviders)
        XCTAssertTrue(state.connectedProviderDescriptors.isEmpty)
    }

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
}

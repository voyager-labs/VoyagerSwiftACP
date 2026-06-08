import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
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

        XCTAssertEqual(saveSpy.saved, [CollectionSearchAISettings(
            provider: .specific(AiProvider.openai.rawValue),
            model: .auto,
            thinking: .providerDefault,
        )])
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

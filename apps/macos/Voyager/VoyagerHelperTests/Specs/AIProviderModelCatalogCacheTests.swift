import Foundation
import VoyagerEntitiesAi
@testable import VoyagerHelper
import VoyagerShared
import XCTest

final class AIProviderModelCatalogCacheTests: XCTestCase {
    func testSelectedModelUsesFirstQueryConversionModelAndReusesCacheForSameSnapshot() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "text-embedding-ada-002"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-3.5-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-search-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        let first = try await cache.selectedModel(for: selection, file: file)
        let second = try await cache.selectedModel(for: selection, file: file)

        XCTAssertEqual(first.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(second.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelReturnsPreferredExplicitModelWhenAvailable() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)
        let preferredModel = AiModelHandle(provider: .openai, rawValue: "gpt-4o")

        let model = try await cache.selectedModel(
            for: selection,
            file: file,
            preferredModel: preferredModel,
        )

        XCTAssertEqual(model.id, preferredModel)
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelThrowsWhenPreferredExplicitModelIsMissing() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)
        let preferredModel = AiModelHandle(provider: .openai, rawValue: "gpt-4o")

        do {
            _ = try await cache.selectedModel(
                for: selection,
                file: file,
                preferredModel: preferredModel,
            )
            XCTFail("Expected explicit preferred model lookup to fail when missing")
        } catch let error as AIProviderModelCatalogCacheError {
            XCTAssertEqual(error, .modelUnavailable(provider: .openai, model: preferredModel))
        }
    }

    func testSelectedModelInvalidatesCacheWhenConnectionsFileSnapshotChanges() async throws {
        let initialFile = Self.makeConnectionsFile(updatedAtMs: 1)
        let updatedFile = Self.makeConnectionsFile(updatedAtMs: 2)
        let fileBox = ConnectionFileBox(initialFile)
        let modelLoader = ModelLoadRecorder(sequence: [
            [.openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")]],
            [.openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o")]],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let initialSelection = try XCTUnwrap(AIProviderQuerySelection.select(from: initialFile).successValue)
        let updatedSelection = try XCTUnwrap(AIProviderQuerySelection.select(from: updatedFile).successValue)

        let first = try await cache.selectedModel(for: initialSelection, file: initialFile)
        fileBox.set(updatedFile)
        let second = try await cache.selectedModel(for: updatedSelection, file: updatedFile)

        XCTAssertEqual(first.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(second.id.rawValue, "gpt-4o")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 2)
    }

    func testWarmUpCachesConnectedProviderModelsForLaterSelection() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        try await cache.warmUp()
        let model = try await cache.selectedModel(for: selection, file: file)

        XCTAssertEqual(model.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelThrowsWhenProviderReturnsOnlyNonGenerativeModels() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "text-embedding-ada-002"),
                Self.makeModel(provider: .openai, rawModelID: "whisper-1"),
                Self.makeModel(provider: .openai, rawModelID: "omni-moderation-latest"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-3.5-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-search-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-realtime-preview"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        do {
            _ = try await cache.selectedModel(for: selection, file: file)
            XCTFail("Expected non-generative OpenAI models to be rejected for query conversion")
        } catch let error as AIProviderModelCatalogCacheError {
            XCTAssertEqual(error, .emptyModelList(provider: .openai))
        }
    }

    private static func makeConnectionsFile(updatedAtMs: Int64) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    fileprivate static func makeModel(provider: AiProvider, rawModelID: String) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawModelID),
            provider: provider,
            rawModelID: rawModelID,
            displayName: rawModelID,
            providerDisplayName: provider.rawValue,
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )
    }
}

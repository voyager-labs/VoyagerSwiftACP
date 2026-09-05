import Foundation
import Logging
import VoyagerEntitiesAi

actor AIProviderModelCatalogCache {
    private struct Snapshot: Equatable {
        let updatedAtMs: Int64
        let connectedProviderIds: [AiProvider]
    }

    private var snapshot: Snapshot?
    private var modelsByProvider: [AiProvider: [AiProviderModel]] = [:]
    private let connectionsFileClient: AIConnectionsFileClient
    private let modelListClient: AiProviderModelListClient
    private let logger: Logger

    init(
        connectionsFileClient: AIConnectionsFileClient = .liveValue,
        modelListClient: AiProviderModelListClient = .liveValue,
        logger: Logger = Logger(label: "VoyagerHelper.AIProviderModelCatalogCache"),
    ) {
        self.connectionsFileClient = connectionsFileClient
        self.modelListClient = modelListClient
        self.logger = logger
    }

    func warmUp() async throws {
        let file = try await connectionsFileClient.load()
        try await warmUp(file: file)
    }

    func selectedModel(
        for selection: AIProviderQuerySelectionContext,
        file: AIConnectionsFile,
        preferredModel: AiModelHandle? = nil,
    ) async throws -> AiProviderModel {
        let currentSnapshot = Self.snapshot(for: file)
        resetIfNeeded(snapshot: currentSnapshot)

        if let preferredModel {
            if let model = exactAvailableModel(for: selection.provider, matching: preferredModel) {
                return model
            }

            let models = try await loadModels(for: selection.provider, credential: selection.credential)
            modelsByProvider[selection.provider] = models

            guard let model = exactAvailableModel(for: selection.provider, matching: preferredModel) else {
                throw AIProviderModelCatalogCacheError.modelUnavailable(
                    provider: selection.provider,
                    model: preferredModel,
                )
            }
            return model
        }

        if let model = firstAvailableModel(for: selection.provider) {
            return model
        }

        let models = try await loadModels(for: selection.provider, credential: selection.credential)
        modelsByProvider[selection.provider] = models

        guard let model = firstAvailableModel(for: selection.provider) else {
            throw AIProviderModelCatalogCacheError.emptyModelList(provider: selection.provider)
        }
        return model
    }

    private func warmUp(file: AIConnectionsFile) async throws {
        let currentSnapshot = Self.snapshot(for: file)
        resetIfNeeded(snapshot: currentSnapshot)

        for provider in currentSnapshot.connectedProviderIds {
            guard modelsByProvider[provider] == nil else { continue }
            guard let record = file.providers[provider.rawValue] else { continue }

            do {
                modelsByProvider[provider] = try await loadModels(for: provider, credential: record.credential)
            } catch {
                logger.warning(
                    "[AIProviderModelCatalogCache] model warmup failed provider=\(provider.rawValue) error=\(error)",
                )
            }
        }
    }

    private func resetIfNeeded(snapshot newSnapshot: Snapshot) {
        guard snapshot != newSnapshot else { return }
        snapshot = newSnapshot
        modelsByProvider = [:]
    }

    private func loadModels(
        for provider: AiProvider,
        credential: StoredCredentialPayload?,
    ) async throws -> [AiProviderModel] {
        let models = try await modelListClient.loadModels(provider, credential)
        return models.filter(Self.supportsQueryConversion)
    }

    private func firstAvailableModel(for provider: AiProvider) -> AiProviderModel? {
        modelsByProvider[provider]?.first(where: Self.supportsQueryConversion)
    }

    private func exactAvailableModel(
        for provider: AiProvider,
        matching handle: AiModelHandle,
    ) -> AiProviderModel? {
        modelsByProvider[provider]?.first(where: { $0.id == handle })
    }

    private static func supportsQueryConversion(_ model: AiProviderModel) -> Bool {
        CollectionSearchAISelectionPolicy.supportsQueryConversion(model)
    }

    private static func snapshot(for file: AIConnectionsFile) -> Snapshot {
        let connectedProviderIds = ProviderDescriptor.v1Catalog
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.provider)
            .filter { provider in
                guard let record = file.providers[provider.rawValue] else { return false }
                return record.snapshot.lastKnownStatus == .connected
                    && (record.credential != nil || provider == .chatgptCodex)
            }
        return Snapshot(updatedAtMs: file.updatedAtMs, connectedProviderIds: connectedProviderIds)
    }
}

enum AIProviderModelCatalogCacheError: Error, Equatable {
    case emptyModelList(provider: AiProvider)
    case modelUnavailable(provider: AiProvider, model: AiModelHandle)
}

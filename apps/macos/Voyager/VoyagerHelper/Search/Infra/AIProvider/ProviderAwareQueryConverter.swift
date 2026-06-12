import Foundation
import Logging
import VoyagerEntitiesAi
import VoyagerShared

struct ProviderAwareQueryConverter {
    let queryConversionInterpreter: QueryConversionInterpreter
    let connectionsFileClient: AIConnectionsFileClient
    let providerExecutionClient: AiChatProviderExecutionClient
    let modelCatalogCache: AIProviderModelCatalogCache
    let now: @Sendable () -> Int64
    let uuid: @Sendable () -> UUID
    let logger: Logger

    init(
        queryConversionInterpreter: QueryConversionInterpreter,
        connectionsFileClient: AIConnectionsFileClient = .liveValue,
        providerExecutionClient: AiChatProviderExecutionClient = .liveValue,
        modelCatalogCache: AIProviderModelCatalogCache = AIProviderModelCatalogCache(),
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) },
        uuid: @escaping @Sendable () -> UUID = UUID.init,
        logger: Logger = Logger(label: "VoyagerHelper.ProviderAwareQueryConverter"),
    ) {
        self.queryConversionInterpreter = queryConversionInterpreter
        self.connectionsFileClient = connectionsFileClient
        self.providerExecutionClient = providerExecutionClient
        self.modelCatalogCache = modelCatalogCache
        self.now = now
        self.uuid = uuid
        self.logger = logger
    }

    func convert(request: SearchRequestPayload) async -> QueryConversionResult {
        do {
            let file = try await connectionsFileClient.load()
            return await convert(request: request, file: file)
        } catch {
            logger.error("[ProviderAwareQueryConverter] connections file load failed: \(error)")
            return QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .conversionFailure,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: String(describing: error),
            )
        }
    }

    private func convert(request: SearchRequestPayload, file: AIConnectionsFile) async -> QueryConversionResult {
        guard let settings = request.collectionSearchAISettings else {
            return await resolveAutoSelection(query: request.query, existingFilters: request.filters, file: file)
        }

        switch settings.model {
        case let .specific(providerRawValue, modelRawValue):
            return await resolveExplicitModelSelection(
                query: request.query,
                existingFilters: request.filters,
                providerRawValue: providerRawValue,
                modelRawValue: modelRawValue,
                requestedThinking: settings.thinking.selection,
                file: file,
            )
        case .auto:
            return await resolveProviderPreference(
                query: request.query,
                existingFilters: request.filters,
                settings: settings,
                file: file,
            )
        }
    }
}

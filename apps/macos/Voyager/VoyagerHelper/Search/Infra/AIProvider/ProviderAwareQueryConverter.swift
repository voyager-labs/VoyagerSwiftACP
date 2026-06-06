import Foundation
import Logging
import VoyagerEntitiesAi
import VoyagerShared

struct ProviderAwareQueryConverter {
    private let queryConversionInterpreter: QueryConversionInterpreter
    private let connectionsFileClient: AIConnectionsFileClient
    private let providerExecutionClient: AiChatProviderExecutionClient
    private let modelCatalogCache: AIProviderModelCatalogCache
    private let now: @Sendable () -> Int64
    private let uuid: @Sendable () -> UUID
    private let logger: Logger

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

    func convert(
        query: String,
        existingFilters: SearchFiltersPayload,
    ) async -> QueryConversionResult {
        do {
            let file = try await connectionsFileClient.load()
            switch AIProviderQuerySelection.select(from: file) {
            case let .success(selection):
                return await convert(
                    query: query,
                    existingFilters: existingFilters,
                    selection: selection,
                    file: file,
                )

            case let .failure(error):
                return mappedSelectionFailure(error)
            }
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

    private func convert(
        query: String,
        existingFilters: SearchFiltersPayload,
        selection: AIProviderQuerySelectionContext,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        do {
            let prompt = try queryConversionInterpreter.buildPrompt(query: query, existingFilters: existingFilters)
            let model = try await modelCatalogCache.selectedModel(for: selection, file: file)
            let request = makeRequest(query: query, selection: selection, model: model.id, prompt: prompt)
            let stream = try providerExecutionClient.execute(request, selection.credential)
            let assistantText = try await collectFinalAssistantText(from: stream)
            let parsed = try queryConversionInterpreter.decodeAndNormalize(
                content: assistantText,
                existingFilters: existingFilters,
            )
            return QueryConversionResult(
                conditions: parsed.conditions,
                scopes: parsed.scopes,
                error: parsed.error,
                outcome: parsed.outcome,
                providerId: selection.provider.rawValue,
                errorCode: parsed.errorCode,
                reason: parsed.reason,
            )
        } catch let error as AIProviderModelCatalogCacheError {
            logger.error("[ProviderAwareQueryConverter] provider model catalog failed: \(error)")
            return mappedModelCatalogFailure(error, provider: selection.provider)
        } catch let error as AiProviderModelListError {
            logger.error("[ProviderAwareQueryConverter] provider model list failed: \(error)")
            return mappedModelListFailure(error, provider: selection.provider)
        } catch let error as AiChatProviderPreflightError {
            logger.error("[ProviderAwareQueryConverter] provider preflight failed: \(error)")
            return mappedPreflightFailure(error, provider: selection.provider)
        } catch let error as AiChatExecutionFailure {
            logger.error("[ProviderAwareQueryConverter] provider execution failed: \(error.rawValue)")
            return mappedExecutionFailure(error, provider: selection.provider)
        } catch {
            logger.error("[ProviderAwareQueryConverter] conversion failed: \(error)")
            return QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Couldn't interpret that query. Try being more specific.",
                outcome: .conversionFailure,
                providerId: selection.provider.rawValue,
                errorCode: "LLM_CONVERSION_FAILED",
                reason: String(describing: error),
            )
        }
    }

    private func makeRequest(
        query: String,
        selection: AIProviderQuerySelectionContext,
        model: AiModelHandle,
        prompt: QueryConversionPromptPayload,
    ) -> AiChatRequest {
        let context = AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: uuid()),
            runID: AiChatRunID(rawValue: uuid()),
            provider: selection.provider,
            model: model,
            sessionStatus: .idle,
            currentContext: .init(),
            promptSummary: query,
            submittedAtMs: now(),
        )
        return AiChatRequest(
            context: context,
            messages: [
                .init(role: .system, content: prompt.systemPrompt),
                .init(role: .user, content: prompt.userPrompt),
            ],
            responseContract: QueryConversionConfig.responseContract,
        )
    }

    private func collectFinalAssistantText(
        from stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    ) async throws -> String {
        for try await event in stream {
            switch event {
            case .requestPrepared, .started, .delta:
                continue
            case let .final(response):
                return response.assistantMessage.content
            case let .failed(_, reason):
                throw reason
            }
        }
        throw AiChatExecutionFailure.transportError
    }
}

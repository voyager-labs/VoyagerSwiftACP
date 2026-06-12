import Foundation
import Logging
import VoyagerEntitiesAi
import VoyagerShared

extension ProviderAwareQueryConverter {
    func resolveDefaultAutoSelection(
        query: String,
        existingFilters: SearchFiltersPayload,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        switch AIProviderQuerySelection.select(from: file) {
        case let .success(selection):
            await convertAutoCandidate(query: query, existingFilters: existingFilters, selection: selection, file: file)
                ?? mappedSelectionFailure(.notConfigured)
        case let .failure(error):
            mappedSelectionFailure(error)
        }
    }

    func convertAutoCandidate(
        query: String,
        existingFilters: SearchFiltersPayload,
        selection: AIProviderQuerySelectionContext,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult? {
        do {
            let model = try await modelCatalogCache.selectedModel(for: selection, file: file)
            return await performConversion(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                model: model,
                requestedThinking: nil,
            )
        } catch {
            return mapAutoSelectionError(error, provider: selection.provider)
        }
    }

    func convertExplicitProvider(
        query: String,
        existingFilters: SearchFiltersPayload,
        selection: AIProviderQuerySelectionContext,
        requestedThinking: AiThinkingSelection?,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        do {
            let model = try await modelCatalogCache.selectedModel(for: selection, file: file)
            return await performConversion(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                model: model,
                requestedThinking: requestedThinking,
            )
        } catch {
            return mapExplicitProviderError(error, provider: selection.provider)
        }
    }

    func convertExplicitModel(
        query: String,
        existingFilters: SearchFiltersPayload,
        selection: AIProviderQuerySelectionContext,
        modelHandle: AiModelHandle,
        requestedThinking: AiThinkingSelection?,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        do {
            let model = try await modelCatalogCache.selectedModel(
                for: selection,
                file: file,
                preferredModel: modelHandle,
            )
            return await performConversion(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                model: model,
                requestedThinking: requestedThinking,
            )
        } catch {
            return mapExplicitModelError(error, provider: selection.provider, model: modelHandle)
        }
    }

    func performConversion(
        query: String,
        existingFilters: SearchFiltersPayload,
        selection: AIProviderQuerySelectionContext,
        model: AiProviderModel,
        requestedThinking: AiThinkingSelection?,
    ) async -> QueryConversionResult {
        let selectedThinking = normalizedThinking(for: model, requestedThinking: requestedThinking)

        do {
            let prompt = try queryConversionInterpreter.buildPrompt(query: query, existingFilters: existingFilters)
            let request = makeRequest(query: query, model: model, thinking: selectedThinking, prompt: prompt)
            let stream = try providerExecutionClient.execute(request, selection.credential)
            let assistantText = try await collectFinalAssistantText(from: stream)
            return try decodeConversion(
                assistantText: assistantText,
                existingFilters: existingFilters,
                provider: selection.provider,
            )
        } catch let error as AiChatProviderPreflightError {
            logger.error("[ProviderAwareQueryConverter] provider preflight failed: \(error)")
            return mappedPreflightFailure(error, provider: selection.provider)
        } catch let error as AiChatExecutionFailure {
            logger.error("[ProviderAwareQueryConverter] provider execution failed: \(error.rawValue)")
            return mappedExecutionFailure(error, provider: selection.provider)
        } catch {
            logger.error("[ProviderAwareQueryConverter] conversion failed: \(error)")
            return conversionFailure(error, provider: selection.provider)
        }
    }
}

private extension ProviderAwareQueryConverter {
    func mapAutoSelectionError(_ error: Error, provider: AiProvider) -> QueryConversionResult {
        if let error = error as? AIProviderModelCatalogCacheError {
            logger.error("[ProviderAwareQueryConverter] auto model catalog failed: \(error)")
            return mappedModelCatalogFailure(error, provider: provider)
        }
        if let error = error as? AiProviderModelListError {
            logger.error("[ProviderAwareQueryConverter] auto model list failed: \(error)")
            return mappedModelListFailure(error, provider: provider)
        }
        logger.error("[ProviderAwareQueryConverter] auto selection failed: \(error)")
        return providerUnavailable(error)
    }

    func mapExplicitProviderError(_ error: Error, provider: AiProvider) -> QueryConversionResult {
        if let error = error as? AIProviderModelCatalogCacheError {
            logger.error("[ProviderAwareQueryConverter] provider model catalog failed: \(error)")
            return mappedExplicitModelFailure(error, provider: provider)
        }
        if let error = error as? AiProviderModelListError {
            logger.error("[ProviderAwareQueryConverter] provider model list failed: \(error)")
            return mappedModelListFailure(error, provider: provider)
        }
        logger.error("[ProviderAwareQueryConverter] selection failed: \(error)")
        return explicitProviderUnavailable(providerRawValue: provider.rawValue, reason: String(describing: error))
    }

    func mapExplicitModelError(
        _ error: Error,
        provider: AiProvider,
        model: AiModelHandle,
    ) -> QueryConversionResult {
        if let error = error as? AIProviderModelCatalogCacheError {
            logger.error("[ProviderAwareQueryConverter] explicit model lookup failed: \(error)")
            return mappedExplicitModelFailure(error, provider: provider, model: model)
        }
        if let error = error as? AiProviderModelListError {
            logger.error("[ProviderAwareQueryConverter] provider model list failed: \(error)")
            return mappedModelListFailure(error, provider: provider)
        }
        logger.error("[ProviderAwareQueryConverter] selection failed: \(error)")
        return explicitModelUnavailable(provider: provider, model: model, reason: String(describing: error))
    }

    func makeRequest(
        query: String,
        model: AiProviderModel,
        thinking: AiThinkingSelection?,
        prompt: QueryConversionPromptPayload,
    ) -> AiChatRequest {
        let context = AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: uuid()),
            runID: AiChatRunID(rawValue: uuid()),
            provider: model.provider,
            model: model.id,
            selectedModel: model,
            selectedThinking: thinking,
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

    func normalizedThinking(
        for model: AiProviderModel,
        requestedThinking: AiThinkingSelection?,
    ) -> AiThinkingSelection? {
        CollectionSearchAISelectionPolicy.normalizeSelectedThinking(requestedThinking, for: model)
    }

    func collectFinalAssistantText(
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

    func decodeConversion(
        assistantText: String,
        existingFilters: SearchFiltersPayload,
        provider: AiProvider,
    ) throws -> QueryConversionResult {
        let parsed = try queryConversionInterpreter.decodeAndNormalize(
            content: assistantText,
            existingFilters: existingFilters,
        )
        return QueryConversionResult(
            conditions: parsed.conditions,
            scopes: parsed.scopes,
            error: parsed.error,
            outcome: parsed.outcome,
            providerId: provider.rawValue,
            errorCode: parsed.errorCode,
            reason: parsed.reason,
        )
    }

    func providerUnavailable(_ error: Error) -> QueryConversionResult {
        QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: "AI provider is unavailable. Check the connection and try again.",
            outcome: .providerUnavailable,
            errorCode: "AI_PROVIDER_UNAVAILABLE",
            reason: String(describing: error),
        )
    }

    func conversionFailure(_ error: Error, provider: AiProvider) -> QueryConversionResult {
        QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: "Couldn't interpret that query. Try being more specific.",
            outcome: .conversionFailure,
            providerId: provider.rawValue,
            errorCode: "LLM_CONVERSION_FAILED",
            reason: String(describing: error),
        )
    }
}

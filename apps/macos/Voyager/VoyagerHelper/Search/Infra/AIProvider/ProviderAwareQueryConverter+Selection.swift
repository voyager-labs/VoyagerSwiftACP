import VoyagerEntitiesAi
import VoyagerShared

extension ProviderAwareQueryConverter {
    func resolveProviderPreference(
        query: String,
        existingFilters: SearchFiltersPayload,
        settings: CollectionSearchAISettingsPayload,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        switch settings.provider {
        case let .specific(providerRawValue):
            guard let provider = AiProvider(rawValue: providerRawValue) else {
                return explicitProviderUnavailable(providerRawValue: providerRawValue, reason: "invalidProvider")
            }
            return await resolveExplicitProviderSelection(
                query: query,
                existingFilters: existingFilters,
                provider: provider,
                requestedThinking: settings.thinking.selection,
                file: file,
            )
        case .auto:
            return await resolveAutoSelection(query: query, existingFilters: existingFilters, file: file)
        }
    }

    func resolveAutoSelection(
        query: String,
        existingFilters: SearchFiltersPayload,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        let candidates = AIProviderQuerySelection.autoCandidates(from: file)
        guard candidates.isEmpty == false else {
            return await resolveDefaultAutoSelection(query: query, existingFilters: existingFilters, file: file)
        }

        var lastFailure: QueryConversionResult?
        for selection in candidates {
            if let result = await convertAutoCandidate(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                file: file,
            ) {
                if result.error == nil { return result }
                lastFailure = result
            }
        }
        return lastFailure ?? mappedSelectionFailure(.notConfigured)
    }

    func resolveExplicitProviderSelection(
        query: String,
        existingFilters: SearchFiltersPayload,
        provider: AiProvider,
        requestedThinking: AiThinkingSelection?,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        switch AIProviderQuerySelection.select(provider: provider, from: file) {
        case let .success(selection):
            await convertExplicitProvider(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                requestedThinking: requestedThinking,
                file: file,
            )
        case let .failure(error):
            mappedExplicitProviderFailure(error, provider: provider)
        }
    }

    func resolveExplicitModelSelection(
        query: String,
        existingFilters: SearchFiltersPayload,
        providerRawValue: String,
        modelRawValue: String,
        requestedThinking: AiThinkingSelection?,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        guard let provider = AiProvider(rawValue: providerRawValue) else {
            return explicitProviderUnavailable(providerRawValue: providerRawValue, reason: "invalidProvider")
        }
        return await resolveExplicitModelSelection(
            query: query,
            existingFilters: existingFilters,
            provider: provider,
            modelRawValue: modelRawValue,
            requestedThinking: requestedThinking,
            file: file,
        )
    }

    func resolveExplicitModelSelection(
        query: String,
        existingFilters: SearchFiltersPayload,
        provider: AiProvider,
        modelRawValue: String,
        requestedThinking: AiThinkingSelection?,
        file: AIConnectionsFile,
    ) async -> QueryConversionResult {
        let modelHandle = AiModelHandle(provider: provider, rawValue: modelRawValue)
        switch AIProviderQuerySelection.select(provider: provider, from: file) {
        case let .success(selection):
            return await convertExplicitModel(
                query: query,
                existingFilters: existingFilters,
                selection: selection,
                modelHandle: modelHandle,
                requestedThinking: requestedThinking,
                file: file,
            )
        case let .failure(error):
            return mappedExplicitProviderFailure(error, provider: provider)
        }
    }
}

extension CollectionSearchAIThinkingPreferencePayload {
    var selection: AiThinkingSelection? {
        switch self {
        case .providerDefault:
            nil
        case .none:
            AiThinkingSelection.none
        case let .effort(value):
            AiThinkingEffort(rawValue: value).map(AiThinkingSelection.effort)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}

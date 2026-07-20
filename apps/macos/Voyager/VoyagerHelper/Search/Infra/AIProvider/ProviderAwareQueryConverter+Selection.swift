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
            let context = ProviderAwareQueryConversionContext(
                query: query,
                existingFilters: existingFilters,
                file: file,
                requestedThinking: settings.thinking.selection,
            )
            return await resolveExplicitProviderSelection(
                context: context,
                provider: provider,
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
        context: ProviderAwareQueryConversionContext,
        provider: AiProvider,
    ) async -> QueryConversionResult {
        switch AIProviderQuerySelection.select(provider: provider, from: context.file) {
        case let .success(selection):
            await convertExplicitProvider(
                query: context.query,
                existingFilters: context.existingFilters,
                selection: selection,
                requestedThinking: context.requestedThinking,
                file: context.file,
            )
        case let .failure(error):
            mappedExplicitProviderFailure(error, provider: provider)
        }
    }

    func resolveExplicitModelSelection(
        context: ProviderAwareQueryConversionContext,
        providerRawValue: String,
        modelRawValue: String,
    ) async -> QueryConversionResult {
        guard let provider = AiProvider(rawValue: providerRawValue) else {
            return explicitProviderUnavailable(providerRawValue: providerRawValue, reason: "invalidProvider")
        }
        return await resolveExplicitModelSelection(
            context: context,
            provider: provider,
            modelRawValue: modelRawValue,
        )
    }

    func resolveExplicitModelSelection(
        context: ProviderAwareQueryConversionContext,
        provider: AiProvider,
        modelRawValue: String,
    ) async -> QueryConversionResult {
        let modelHandle = AiModelHandle(provider: provider, rawValue: modelRawValue)
        switch AIProviderQuerySelection.select(provider: provider, from: context.file) {
        case let .success(selection):
            return await convertExplicitModel(
                context: context,
                selection: selection,
                modelHandle: modelHandle,
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

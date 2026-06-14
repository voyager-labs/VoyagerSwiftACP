import VoyagerEntitiesAi

extension ProviderAwareQueryConverter {
    func mappedSelectionFailure(_ error: AIProviderQuerySelectionError) -> QueryConversionResult {
        switch error {
        case .notConfigured:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Connect an AI provider in Settings to use natural-language search.",
                outcome: .providerNotConfigured,
                errorCode: "AI_PROVIDER_NOT_CONFIGURED",
            )
        case let .invalidCredential(provider, expected):
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: expected.rawValue,
            )
        case let .providerUnavailable(provider, reason):
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .providerUnavailable,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: reason.rawValue,
            )
        }
    }

    func mappedExplicitProviderFailure(
        _ error: AIProviderQuerySelectionError,
        provider: AiProvider,
    ) -> QueryConversionResult {
        switch error {
        case .notConfigured:
            explicitProviderUnavailable(providerRawValue: provider.rawValue, reason: "notConfigured")
        case let .invalidCredential(provider, expected):
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: expected.rawValue,
            )
        case let .providerUnavailable(provider, reason):
            explicitProviderUnavailable(providerRawValue: provider.rawValue, reason: reason.rawValue)
        }
    }

    func mappedExplicitModelFailure(
        _ error: AIProviderModelCatalogCacheError,
        provider: AiProvider,
        model: AiModelHandle? = nil,
    ) -> QueryConversionResult {
        switch error {
        case .emptyModelList:
            explicitModelUnavailable(
                provider: provider,
                model: model ?? AiModelHandle(provider: provider, rawValue: "unknown"),
                reason: "emptyModelList",
            )
        case let .modelUnavailable(provider, model):
            explicitModelUnavailable(
                provider: provider,
                model: model,
                reason: "modelUnavailable",
            )
        }
    }

    func explicitProviderUnavailable(
        providerRawValue: String,
        reason: String,
    ) -> QueryConversionResult {
        QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: "AI provider is unavailable. Check the connection and try again.",
            outcome: .providerUnavailable,
            providerId: providerRawValue,
            errorCode: "COLLECTION_SEARCH_PROVIDER_UNAVAILABLE",
            reason: reason,
        )
    }

    func explicitModelUnavailable(
        provider: AiProvider,
        model: AiModelHandle,
        reason: String,
    ) -> QueryConversionResult {
        QueryConversionResult(
            conditions: [],
            scopes: nil,
            error: "AI provider model is unavailable. Check the model selection and try again.",
            outcome: .providerUnavailable,
            providerId: provider.rawValue,
            errorCode: "COLLECTION_SEARCH_MODEL_UNAVAILABLE",
            reason: "\(reason):\(model.rawValue)",
        )
    }

    func mappedModelCatalogFailure(
        _ error: AIProviderModelCatalogCacheError,
        provider: AiProvider,
    ) -> QueryConversionResult {
        switch error {
        case .emptyModelList:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .providerUnavailable,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: "emptyModelList",
            )
        case let .modelUnavailable(provider, model):
            explicitModelUnavailable(
                provider: provider,
                model: model,
                reason: "modelUnavailable",
            )
        }
    }

    func mappedModelListFailure(
        _ error: AiProviderModelListError,
        provider: AiProvider,
    ) -> QueryConversionResult {
        switch error {
        case .missingCredential, .invalidCredential:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: String(describing: error),
            )
        case .unsupportedProvider, .invalidResponse, .httpError, .networkError:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .providerUnavailable,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: String(describing: error),
            )
        }
    }

    func mappedPreflightFailure(
        _ error: AiChatProviderPreflightError,
        provider: AiProvider,
    ) -> QueryConversionResult {
        switch error {
        case .missingCredential:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: "missingCredential",
            )
        case let .invalidCredential(_, expected):
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: expected.rawValue,
            )
        case let .loweringFailed(loweringError):
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Couldn't interpret that query. Try being more specific.",
                outcome: .conversionFailure,
                providerId: provider.rawValue,
                errorCode: "LLM_CONVERSION_FAILED",
                reason: String(describing: loweringError),
            )
        }
    }

    func mappedExecutionFailure(
        _ failure: AiChatExecutionFailure,
        provider: AiProvider,
    ) -> QueryConversionResult {
        switch failure {
        case .cancelled:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .providerUnavailable,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: failure.rawValue,
            )
        case .authentication:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "Reconnect your AI provider in Settings, then try again.",
                outcome: .invalidCredential,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_INVALID_CREDENTIAL",
                reason: failure.rawValue,
            )
        case .modelUnavailable, .unsupportedProvider, .cliUnavailable:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .providerUnavailable,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_UNAVAILABLE",
                reason: failure.rawValue,
            )
        case .network, .rateLimited, .quotaExceeded, .transportError, .sessionMismatch, .invalidRequest, .unknown:
            QueryConversionResult(
                conditions: [],
                scopes: nil,
                error: "AI provider is unavailable. Check the connection and try again.",
                outcome: .networkFailure,
                providerId: provider.rawValue,
                errorCode: "AI_PROVIDER_NETWORK_FAILURE",
                reason: failure.rawValue,
            )
        }
    }
}

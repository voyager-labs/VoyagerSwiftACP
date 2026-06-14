import VoyagerShared

public extension CollectionSearchAISettings {
    var payload: CollectionSearchAISettingsPayload {
        CollectionSearchAISettingsPayload(
            provider: provider.payload,
            model: model.payload,
            thinking: thinking.payload,
        )
    }
}

public extension CollectionSearchAIProviderPreference {
    var payload: CollectionSearchAIProviderPreferencePayload {
        switch self {
        case .auto:
            .auto
        case let .specific(provider):
            .specific(provider)
        }
    }
}

public extension CollectionSearchAIModelPreference {
    var payload: CollectionSearchAIModelPreferencePayload {
        switch self {
        case .auto:
            .auto
        case let .specific(provider, model):
            .specific(provider: provider, model: model)
        }
    }
}

public extension CollectionSearchAIThinkingPreference {
    var payload: CollectionSearchAIThinkingPreferencePayload {
        switch self {
        case .providerDefault:
            .providerDefault
        case .none:
            .none
        case let .effort(value):
            .effort(value)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}

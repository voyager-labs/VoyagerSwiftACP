import Foundation
import VoyagerEntitiesAi

enum AiChatModelCatalogAuthority: Equatable {
    case available(AiProviderModel)
    case confirmedUnavailable
    case unknown
}

enum AiChatStateSelection {
    static func normalizedSelectionHandle(
        _ preferredHandle: AiModelHandle?,
        in models: [AiProviderModel],
    ) -> AiModelHandle? {
        resolvedModel(for: preferredHandle, in: models)?.id
    }

    static func resolvedModel(for handle: AiModelHandle?, in models: [AiProviderModel]) -> AiProviderModel? {
        guard let handle else { return nil }
        return models.first(where: { $0.id == handle && $0.unavailableReason == nil })
    }

    static func modelCatalogAuthority(
        for handle: AiModelHandle,
        state: AiChatState,
    ) -> AiChatModelCatalogAuthority {
        if case let .known(providers) = state.providerConnectionSnapshot,
           !providers.contains(handle.provider)
        {
            return .confirmedUnavailable
        }
        if state.modelListPendingProviders.contains(handle.provider) {
            return .unknown
        }
        if state.modelListFailedProviders[handle.provider] != nil {
            return .unknown
        }
        if let models = state.modelListLoadedModelsByProvider[handle.provider] {
            return providerCatalogAuthority(for: handle, in: models)
        }
        if let models = state.availableModelsByProvider[handle.provider] {
            return providerCatalogAuthority(for: handle, in: models)
        }

        switch state.modelListState {
        case let .loaded(models):
            if let model = resolvedModel(for: handle, in: models) {
                return .available(model)
            }
            return models.contains(where: { $0.provider == handle.provider })
                ? .confirmedUnavailable
                : .unknown
        case .empty:
            return .confirmedUnavailable
        case .idle, .loading, .failed:
            return .unknown
        }
    }

    static func revalidatedNewChatSelectionSeed(
        _ seed: AiChatNewChatSelectionSeed?,
        state: AiChatState,
    ) -> AiChatNewChatSelectionSeed? {
        guard let seed else { return nil }

        switch modelCatalogAuthority(for: seed.modelHandle, state: state) {
        case let .available(model):
            return AiChatNewChatSelectionSeedResolver.revalidate(seed, catalog: [model])
        case .confirmedUnavailable:
            return nil
        case .unknown:
            return seed
        }
    }

    static func resolvedModelRow(for handle: AiModelHandle?, in rows: [AiModelCatalogRow]) -> AiModelCatalogRow? {
        guard let handle else { return nil }
        return rows.first(where: { $0.handle == handle })
    }

    static func containsModelHandle(_ handle: AiModelHandle, in models: [AiProviderModel]) -> Bool {
        models.contains(where: { $0.id == handle })
    }

    static func containsModelHandle(_ handle: AiModelHandle, in rows: [AiModelCatalogRow]) -> Bool {
        rows.contains(where: { $0.handle == handle })
    }

    static func normalizeSelectedThinking(
        _ selectedThinking: AiThinkingSelection?,
        for model: AiProviderModel?,
    ) -> AiThinkingSelection? {
        guard let model else { return nil }
        return AiThinkingSelectionPolicy.normalize(
            selectedThinking,
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        )
    }

    static func modelListState(from catalogRows: [AiModelCatalogRow]) -> AiChatModelListState {
        let models = catalogRows.map { row in
            let providerDisplayName = ProviderDescriptor.descriptor(for: row.handle.provider)?.displayName
                ?? row.handle.provider.rawValue
            return AiProviderModel(
                id: row.handle,
                provider: row.handle.provider,
                rawModelID: row.handle.rawValue,
                displayName: row.displayName,
                providerDisplayName: providerDisplayName,
                thinkingCapability: .unknown(reason: .init(message: "Thinking capability metadata is not loaded yet.")),
                unavailableReason: nil,
            )
        }
        return models.isEmpty ? .empty : .loaded(models)
    }

    static func makeCatalogRows(
        for models: [AiProviderModel],
        preserving existingRows: [AiModelCatalogRow] = [],
    ) -> [AiModelCatalogRow] {
        models.enumerated().map { index, model in
            if let existingRow = existingRows.first(where: { $0.handle == model.id }) {
                return AiModelCatalogRow(
                    handle: existingRow.handle,
                    displayName: model.displayName,
                    authMethod: existingRow.authMethod,
                    subtitle: existingRow.subtitle,
                    sortOrder: existingRow.sortOrder,
                    isDefault: existingRow.isDefault,
                    isRecommended: existingRow.isRecommended,
                )
            }
            return AiModelCatalogRow(
                handle: model.id,
                displayName: model.displayName,
                authMethod: ProviderDescriptor.descriptor(for: model.provider)?.authMethod ?? .apiKey,
                subtitle: nil,
                sortOrder: index,
                isDefault: false,
                isRecommended: false,
            )
        }
    }

    static func makeCatalogRows(for modelListState: AiChatModelListState) -> [AiModelCatalogRow] {
        switch modelListState {
        case let .loaded(models):
            makeCatalogRows(for: models)
        case .idle, .loading, .empty, .failed:
            []
        }
    }

    static func defaultThinkingLabel(for capability: AiModelThinkingCapability) -> String {
        AiThinkingSelectionPolicy.defaultLabel(for: capability)
    }

    static func thinkingLabel(for selection: AiThinkingSelection) -> String {
        AiThinkingSelectionPolicy.label(for: selection)
    }

    private static func providerCatalogAuthority(
        for handle: AiModelHandle,
        in models: [AiProviderModel],
    ) -> AiChatModelCatalogAuthority {
        guard let model = resolvedModel(for: handle, in: models) else {
            return .confirmedUnavailable
        }
        return .available(model)
    }
}

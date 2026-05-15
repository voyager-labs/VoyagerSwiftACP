import Foundation
import VoyagerEntitiesAi

enum AiChatStateSelection {
    static func normalizedSelectionHandle(
        _ preferredHandle: AiModelHandle?,
        in models: [AiProviderModel]
    ) -> AiModelHandle? {
        resolvedModel(for: preferredHandle, in: models)?.id
    }

    static func resolvedModel(for handle: AiModelHandle?, in models: [AiProviderModel]) -> AiProviderModel? {
        guard let handle else { return nil }
        return models.first(where: { $0.id == handle })
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
        for model: AiProviderModel?
    ) -> AiThinkingSelection? {
        guard let selectedThinking, let model else { return nil }

        switch (selectedThinking, model.thinkingCapability) {
        case (.none, .effort), (.none, .adaptive), (.none, .tokenBudget), (.none, .unknown):
            return selectedThinking
        case let (.effort(value), .effort(values, _)):
            return values.contains(value) ? selectedThinking : nil
        case let (.effort(value), .adaptive(values, _)):
            return values.contains(value) ? selectedThinking : nil
        case let (.tokenBudget(value), .tokenBudget(min, max, _)):
            return (min ... max).contains(value) ? selectedThinking : nil
        case (.effort, .unknown), (.tokenBudget, .unknown):
            return selectedThinking
        case (.none, .unsupported), (.effort, .tokenBudget), (.tokenBudget, .effort), (.tokenBudget, .adaptive),
             (.effort, .unsupported), (.tokenBudget, .unsupported):
            return nil
        }
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
                unavailableReason: nil
            )
        }
        return models.isEmpty ? .empty : .loaded(models)
    }

    static func makeCatalogRows(
        for models: [AiProviderModel],
        preserving existingRows: [AiModelCatalogRow] = []
    ) -> [AiModelCatalogRow] {
        models.enumerated().map { index, model in
            if let existingRow = existingRows.first(where: { $0.handle == model.id }) {
                return existingRow
            }
            return AiModelCatalogRow(
                handle: model.id,
                displayName: model.displayName,
                authMethod: ProviderDescriptor.descriptor(for: model.provider)?.authMethod ?? .apiKey,
                subtitle: nil,
                sortOrder: index,
                isDefault: false,
                isRecommended: false
            )
        }
    }

    static func makeCatalogRows(for modelListState: AiChatModelListState) -> [AiModelCatalogRow] {
        switch modelListState {
        case let .loaded(models):
            return makeCatalogRows(for: models)
        case .idle, .loading, .empty, .failed:
            return []
        }
    }

    static func defaultThinkingLabel(for capability: AiModelThinkingCapability) -> String {
        switch capability {
        case .unsupported, .unknown:
            return "Thinking unavailable"
        case .effort, .adaptive, .tokenBudget:
            return "default"
        }
    }

    static func thinkingLabel(for selection: AiThinkingSelection) -> String {
        switch selection {
        case .none:
            return "none"
        case let .effort(value):
            switch value {
            case .minimal:
                return "minimal"
            case .low:
                return "low"
            case .medium:
                return "medium"
            case .high:
                return "high"
            case .xhigh:
                return "x-high"
            case .max:
                return "max"
            }
        case let .tokenBudget(value):
            return "\(value) tokens"
        }
    }
}

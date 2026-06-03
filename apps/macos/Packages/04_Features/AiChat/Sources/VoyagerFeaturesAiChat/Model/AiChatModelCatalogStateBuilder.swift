import Foundation
import VoyagerEntitiesAi

struct AiChatModelCatalogStateBuilder {
    let state: AiChatState
    let availableModels: [AiProviderModel]

    var modelCatalogState: AiChatModelCatalogState {
        let selectedModel = selectedModelDisplayModel
        let lockedModel = lockedModelDisplayModel
        let selectedHandle = selectedModel?.handle
        let lockedHandle = lockedModel?.handle
        let rows: [AiChatModelCatalogRowDisplayModel] = switch state.modelListState {
        case .loaded:
            state.catalogRows.map { row in
                let label = aiChatModelLabel(for: row)
                return AiChatModelCatalogRowDisplayModel(
                    handle: row.handle,
                    label: label,
                    providerBadge: label.subtitle,
                    isSelected: row.handle == selectedHandle,
                    isLocked: row.handle == lockedHandle,
                    isDefault: row.isDefault,
                    isRecommended: row.isRecommended,
                )
            }
        case .idle, .loading, .empty, .failed:
            []
        }
        let rowsByHandle = Dictionary(uniqueKeysWithValues: rows.map { ($0.handle, $0) })
        let sections = modelCatalogSections(rowsByHandle: rowsByHandle)

        return AiChatModelCatalogState(
            fieldLabel: "Model",
            rows: rows,
            sections: sections,
            selectedModel: selectedModel,
            lockedModel: lockedModel,
        )
    }

    var modelSelectorContentState: AiChatModelSelectorContentState {
        switch state.modelListState {
        case .idle, .loading:
            return .loading(.init(
                title: "Loading models",
                detail: "Fetching available models from connected providers.",
            ))
        case .empty:
            return .empty(.init(
                title: "No models available",
                detail: "No selectable models are available for the current provider setup.",
            ))
        case let .failed(failure):
            if failure.reason == .unsupportedProvider {
                return .unsupported(.init(title: "Provider unsupported", detail: failure.message))
            }
            return .failed(.init(title: "Models unavailable", detail: failure.message))
        case .loaded:
            let sections = modelCatalogState.sections
            if sections.isEmpty {
                return .empty(.init(
                    title: "No models available",
                    detail: "No selectable models are available for the current provider setup.",
                ))
            }
            return .loaded(sections)
        }
    }

    var modelSelectorIsDisabled: Bool {
        switch modelSelectorContentState {
        case .empty:
            true
        case let .loaded(sections):
            sections.isEmpty
        case .loading, .failed, .unsupported:
            false
        }
    }

    var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        guard let model = state.resolvedModel(for: state.selectedModelHandle) else { return nil }
        return AiChatSelectedModelDisplayModel(handle: model.id, label: AiChatModelLabel(title: model.displayName))
    }

    var lockedModelDisplayModel: AiChatLockedModelDisplayModel? {
        if case let .processing(lock) = state.executionPhase,
           state.sessionList.rows.isEmpty || state.sessionID == lock.context.sessionID
        {
            return lockedModelDisplayModel(for: lock)
        }
        guard let row = state.resolvedModelRow(for: state.lockedModelHandle) else { return nil }
        return AiChatLockedModelDisplayModel(handle: row.handle, label: AiChatModelLabel(title: row.displayName))
    }

    func lockedModelDisplayModel(for lock: AiChatRequestLock) -> AiChatLockedModelDisplayModel {
        if let row = lock.selectedModelRow ?? state.resolvedModelRow(for: lock.selectedModelHandle) {
            return AiChatLockedModelDisplayModel(handle: row.handle, label: AiChatModelLabel(title: row.displayName))
        }
        return AiChatLockedModelDisplayModel(
            handle: lock.selectedModelHandle,
            label: AiChatModelLabel(title: lock.selectedModelHandle.rawValue),
        )
    }

    private func modelCatalogSections(
        rowsByHandle: [AiModelHandle: AiChatModelCatalogRowDisplayModel],
    ) -> [AiChatModelCatalogSectionDisplayModel] {
        guard case .loaded = state.modelListState else { return [] }
        let discoveredProviders = availableModels.reduce(into: [AiProvider]()) { providers, model in
            if !providers.contains(model.provider) { providers.append(model.provider) }
        }
        let groupedProviders: [AiProvider] = switch state.providerConnectionSnapshot {
        case let .known(providers):
            providers + discoveredProviders.filter { !providers.contains($0) }
        case .unknown:
            discoveredProviders
        }
        return groupedProviders.compactMap { provider in
            let providerModels = state.availableModelsByProvider[provider]
                ?? availableModels.filter { $0.provider == provider }
            let providerRows = providerModels.compactMap { model in rowsByHandle[model.id] }
            guard !providerRows.isEmpty else { return nil }
            return AiChatModelCatalogSectionDisplayModel(
                provider: provider,
                title: aiChatProviderSectionTitle(for: provider),
                rows: providerRows,
            )
        }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public extension AiChatState {
    var surfaceState: AiChatSurfaceState {
        displayModelBuilder.surfaceState
    }

    var modelFieldLabel: String {
        displayModelBuilder.modelFieldLabel
    }

    var isProcessing: Bool {
        displayModelBuilder.isProcessing
    }

    var resolvedSelectedModelHandle: AiModelHandle? {
        displayModelBuilder.resolvedSelectedModelHandle
    }

    var resolvedSelectedModel: AiProviderModel? {
        displayModelBuilder.resolvedSelectedModel
    }

    func normalizedSelectionHandle(
        _ preferredHandle: AiModelHandle?,
        in models: [AiProviderModel]? = nil,
    ) -> AiModelHandle? {
        resolvedModel(for: preferredHandle, in: models)?.id
    }

    func normalizedSelectionHandlePreservingCurrentSelection(
        in models: [AiProviderModel],
        preferredHandle: AiModelHandle?,
    ) -> AiModelHandle? {
        if let currentHandle = resolvedSelectedModelHandle,
           Self.containsModelHandle(currentHandle, in: models)
        {
            return currentHandle
        }
        return normalizedSelectionHandle(preferredHandle, in: models)
    }

    func resolvedModel(for handle: AiModelHandle?, in models: [AiProviderModel]? = nil) -> AiProviderModel? {
        Self.resolvedModel(for: handle, in: models ?? availableModels)
    }

    func resolvedModelRow(for handle: AiModelHandle?, in rows: [AiModelCatalogRow]? = nil) -> AiModelCatalogRow? {
        Self.resolvedModelRow(for: handle, in: rows ?? catalogRows)
    }

    static func normalizedSelectionHandle(
        _ preferredHandle: AiModelHandle?,
        in models: [AiProviderModel],
    ) -> AiModelHandle? {
        AiChatStateSelection.normalizedSelectionHandle(preferredHandle, in: models)
    }

    static func resolvedModel(for handle: AiModelHandle?, in models: [AiProviderModel]) -> AiProviderModel? {
        AiChatStateSelection.resolvedModel(for: handle, in: models)
    }

    static func resolvedModelRow(for handle: AiModelHandle?, in rows: [AiModelCatalogRow]) -> AiModelCatalogRow? {
        AiChatStateSelection.resolvedModelRow(for: handle, in: rows)
    }

    static func containsModelHandle(_ handle: AiModelHandle, in models: [AiProviderModel]) -> Bool {
        AiChatStateSelection.containsModelHandle(handle, in: models)
    }

    static func containsModelHandle(_ handle: AiModelHandle, in rows: [AiModelCatalogRow]) -> Bool {
        AiChatStateSelection.containsModelHandle(handle, in: rows)
    }

    static func normalizeSelectedThinking(
        _ selectedThinking: AiThinkingSelection?,
        for model: AiProviderModel?,
    ) -> AiThinkingSelection? {
        AiChatStateSelection.normalizeSelectedThinking(selectedThinking, for: model)
    }

    static func modelListState(from catalogRows: [AiModelCatalogRow]) -> AiChatModelListState {
        AiChatStateSelection.modelListState(from: catalogRows)
    }

    static func makeCatalogRows(
        for models: [AiProviderModel],
        preserving existingRows: [AiModelCatalogRow] = [],
    ) -> [AiModelCatalogRow] {
        AiChatStateSelection.makeCatalogRows(for: models, preserving: existingRows)
    }

    static func makeCatalogRows(for modelListState: AiChatModelListState) -> [AiModelCatalogRow] {
        AiChatStateSelection.makeCatalogRows(for: modelListState)
    }

    static func defaultThinkingLabel(for capability: AiModelThinkingCapability) -> String {
        AiChatStateSelection.defaultThinkingLabel(for: capability)
    }

    static func thinkingLabel(for selection: AiThinkingSelection) -> String {
        AiChatStateSelection.thinkingLabel(for: selection)
    }
}

extension AiChatState {
    var displayModelBuilder: AiChatStateDisplayModelBuilder {
        AiChatStateDisplayModelBuilder(state: self)
    }
}

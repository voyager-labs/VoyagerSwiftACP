import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public struct AiModelListFailure: Equatable, Sendable {
    public var message: String
    public var reason: AiModelListFailureReason

    public init(message: String, reason: AiModelListFailureReason = .generic) {
        self.message = message
        self.reason = reason
    }
}

public enum AiModelListFailureReason: Equatable, Sendable {
    case generic
    case unsupportedProvider
}

public enum AiChatProviderConnectionSnapshot: Equatable, Sendable {
    case unknown
    case known([AiProvider])
}

public enum AiChatModelListState: Equatable, Sendable {
    case idle
    case loading
    case loaded([AiProviderModel])
    case empty
    case failed(AiModelListFailure)
}

@ObservableState
public struct AiChatState: Equatable, Sendable {
    public var restoreSessionID: AiChatSessionID?
    public var restoreOutcome: AiChatSessionRestoreResult?
    public var restoreFailure: AiChatSessionRestoreFailure?
    public var sessionID: AiChatSessionID?
    public var sessionStatus: AiChatSessionStatus
    public var currentContext: AiChatCurrentContextSnapshot
    public var transcriptHistory: [AiChatMessage]
    public var draftText: String
    public var catalogRows: [AiModelCatalogRow]
    public var modelListState: AiChatModelListState
    public var isModelSelectorPresented: Bool
    public var selectedModelHandle: AiModelHandle?
    public var selectedThinking: AiThinkingSelection?
    public var unavailableSelectedModelHandle: AiModelHandle?
    public var lockedModelHandle: AiModelHandle?
    public var lastExecutionFailure: AiChatExecutionFailure?
    public var executionPhase: AiChatExecutionPhase
    public var modelListRequestID: UUID?
    public var modelListProvider: AiProvider?
    public var modelListProviderOrder: [AiProvider]
    public var modelListPendingProviders: Set<AiProvider>
    public var modelListLoadedModelsByProvider: [AiProvider: [AiProviderModel]]
    public var modelListFailedProviders: [AiProvider: AiModelListFailure]
    public var providerConnectionSnapshot: AiChatProviderConnectionSnapshot
    public var availableModelsByProvider: [AiProvider: [AiProviderModel]]

    public init(
        restoreSessionID: AiChatSessionID? = nil,
        restoreOutcome: AiChatSessionRestoreResult? = nil,
        restoreFailure: AiChatSessionRestoreFailure? = nil,
        sessionID: AiChatSessionID? = nil,
        sessionStatus: AiChatSessionStatus = .idle,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        transcriptHistory: [AiChatMessage] = [],
        draftText: String = "",
        catalogRows: [AiModelCatalogRow] = [],
        modelListState: AiChatModelListState? = nil,
        isModelSelectorPresented: Bool = false,
        selectedModelHandle: AiModelHandle? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        unavailableSelectedModelHandle: AiModelHandle? = nil,
        lockedModelHandle: AiModelHandle? = nil,
        lastExecutionFailure: AiChatExecutionFailure? = nil,
        executionPhase: AiChatExecutionPhase = .idle,
        modelListRequestID: UUID? = nil,
        modelListProvider: AiProvider? = nil,
        modelListProviderOrder: [AiProvider] = [],
        modelListPendingProviders: Set<AiProvider> = [],
        modelListLoadedModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        modelListFailedProviders: [AiProvider: AiModelListFailure] = [:],
        providerConnectionSnapshot: AiChatProviderConnectionSnapshot = .unknown,
        availableModelsByProvider: [AiProvider: [AiProviderModel]] = [:]
    ) {
        self.restoreSessionID = restoreSessionID
        self.restoreOutcome = restoreOutcome
        self.restoreFailure = restoreFailure
        self.sessionID = sessionID
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.transcriptHistory = transcriptHistory
        self.draftText = draftText
        let resolvedModelListState = modelListState ?? Self.modelListState(from: catalogRows)
        self.catalogRows = catalogRows.isEmpty ? Self.makeCatalogRows(for: resolvedModelListState) : catalogRows
        self.modelListState = resolvedModelListState
        self.isModelSelectorPresented = isModelSelectorPresented
        self.selectedModelHandle = selectedModelHandle
        self.selectedThinking = selectedThinking
        self.unavailableSelectedModelHandle = unavailableSelectedModelHandle
        self.lockedModelHandle = lockedModelHandle
        self.lastExecutionFailure = lastExecutionFailure
        self.executionPhase = executionPhase
        self.modelListRequestID = modelListRequestID
        self.modelListProvider = modelListProvider
        self.modelListProviderOrder = modelListProviderOrder
        self.modelListPendingProviders = modelListPendingProviders
        self.modelListLoadedModelsByProvider = modelListLoadedModelsByProvider
        self.modelListFailedProviders = modelListFailedProviders
        self.providerConnectionSnapshot = providerConnectionSnapshot
        self.availableModelsByProvider = availableModelsByProvider
    }

    public var availableModels: [AiProviderModel] {
        switch modelListState {
        case let .loaded(models):
            models
        case .idle, .loading, .empty, .failed:
            []
        }
    }

    public var currentContextSummaryDisplayModel: AiChatContextSummaryDisplayModel {
        aiChatContextSummaryDisplayModel(for: currentContext)
    }

    public var connectionState: AiChatConnectionState {
        if let metadata = aiChatUnconnectedMetadata(for: self) {
            return .unconnected(metadata)
        }
        if let metadata = aiChatErrorMetadata(for: self) {
            return .error(metadata)
        }
        return .connected
    }

    public var emptyStateDisplayModel: AiChatEmptyStateDisplayModel {
        AiChatEmptyStateDisplayModel(
            title: "Ask about this context",
            detail: "Send a message to start a contextual chat."
        )
    }

    public var chatInputDisplayModel: AiChatInputDisplayModel {
        let stopEnabled = isProcessing && (cancelAffordance?.isEnabled ?? false)
        return AiChatInputDisplayModel(
            placeholder: "Ask anything…",
            contextAffordanceLabel: "+",
            modelLabel: chatInputModelLabel,
            effortLabel: chatInputThinkingLabel,
            submitAccessibilityLabel: "Send",
            stopAccessibilityLabel: "Stop",
            isSubmitVisible: !isProcessing,
            isStopVisible: isProcessing,
            canSubmit: canSubmit,
            canStop: stopEnabled
        )
    }

    public var skeletonDisplayModel: AiChatSkeletonDisplayModel {
        AiChatSkeletonDisplayModel(
            headerTitle: "Chat",
            currentContext: currentContextSummaryDisplayModel,
            surface: skeletonSurfaceDisplayModel,
            chatInput: chatInputDisplayModel
        )
    }

    public var skeletonSurfaceDisplayModel: AiChatSkeletonSurfaceDisplayModel {
        switch surfaceState {
        case let .unconnected(connection, _):
            .unconnected(connection)
        case let .error(connection, _):
            .error(connection)
        case .empty:
            .empty(emptyStateDisplayModel)
        case .ready:
            .ready
        case let .processing(processing, _, _):
            .processing(processing)
        }
    }

    public var modelCatalogState: AiChatModelCatalogState {
        let selectedModel = selectedModelDisplayModel
        let lockedModel = lockedModelDisplayModel
        let selectedHandle = selectedModel?.handle
        let lockedHandle = lockedModel?.handle
        let rows: [AiChatModelCatalogRowDisplayModel] = switch modelListState {
        case .loaded:
            catalogRows.map { row in
                let label = aiChatModelLabel(for: row)
                return AiChatModelCatalogRowDisplayModel(
                    handle: row.handle,
                    label: label,
                    providerBadge: label.subtitle,
                    isSelected: row.handle == selectedHandle,
                    isLocked: row.handle == lockedHandle,
                    isDefault: row.isDefault,
                    isRecommended: row.isRecommended
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
            lockedModel: lockedModel
        )
    }

    public var modelSelectorContentState: AiChatModelSelectorContentState {
        switch modelListState {
        case .idle, .loading:
            return .loading(.init(
                title: "Loading models",
                detail: "Fetching available models from connected providers."
            ))
        case .empty:
            return .empty(.init(
                title: "No models available",
                detail: "No selectable models are available for the current provider setup."
            ))
        case let .failed(failure):
            if failure.reason == .unsupportedProvider {
                return .unsupported(.init(
                    title: "Provider unsupported",
                    detail: failure.message
                ))
            }

            return .failed(.init(
                title: "Models unavailable",
                detail: failure.message
            ))
        case .loaded:
            let sections = modelCatalogState.sections
            if sections.isEmpty {
                return .empty(.init(
                    title: "No models available",
                    detail: "No selectable models are available for the current provider setup."
                ))
            }
            return .loaded(sections)
        }
    }

    public var modelSelectorHasPresentableContent: Bool {
        modelSelectorContentState.hasPresentableContent
    }

    public var modelSelectorIsDisabled: Bool {
        switch modelSelectorContentState {
        case .empty:
            return true
        case let .loaded(sections):
            return sections.isEmpty
        case .loading, .failed, .unsupported:
            return false
        }
    }

    public var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        guard let model = resolvedSelectedModel else { return nil }
        return AiChatSelectedModelDisplayModel(handle: model.id, label: AiChatModelLabel(title: model.displayName))
    }

    public var lockedModelDisplayModel: AiChatLockedModelDisplayModel? {
        if case let .processing(lock) = executionPhase {
            return lockedModelDisplayModel(for: lock)
        }

        guard let row = resolvedModelRow(for: lockedModelHandle) else { return nil }
        return AiChatLockedModelDisplayModel(handle: row.handle, label: AiChatModelLabel(title: row.displayName))
    }

    public var canSubmit: Bool {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isProcessing else { return false }
        guard case .loaded = modelListState else { return false }
        guard resolvedSelectedModel != nil else { return false }
        guard connectionState == .connected else { return false }

        switch surfaceState {
        case .empty, .ready:
            return true
        case .unconnected, .error, .processing:
            return false
        }
    }

    public var canRegenerate: Bool {
        !isProcessing && transcriptHistory.contains(where: { $0.role == .assistant })
    }

    public var requestStatusText: String? {
        switch executionPhase {
        case .idle:
            if sessionStatus == .restoring {
                return "Restoring session"
            }
            return nil
        case let .processing(lock):
            return "Processing \(lock.selectedModelRow?.displayName ?? lock.selectedModelHandle.rawValue)"
        case .completed:
            return "Request complete"
        case let .failed(_, failure):
            return failure.displayMessage
        case .cancelled:
            return "Request cancelled"
        case let .persistenceRecovery(_, failure):
            return "Finalized locally; \(failure.displayMessage)"
        }
    }

    public var sessionStatusText: String? {
        if sessionStatus == .restoring {
            return "Restoring session"
        }

        switch restoreOutcome {
        case .restored:
            return "Restored session"
        case .newSession:
            return "Started new session"
        case .rebindRequired:
            return "Session needs rebind"
        case .failed:
            return nil
        case nil:
            return nil
        }
    }

    public var cancelAffordance: AiChatCancelAffordance? {
        guard executionPhase.isProcessing else { return nil }
        return AiChatCancelAffordance(title: "Cancel request", isEnabled: true)
    }

    public var surfaceState: AiChatSurfaceState {
        switch executionPhase {
        case let .processing(lock):
            return .processing(
                processing: AiChatProcessingState(
                    lockedModel: lockedModelDisplayModel(for: lock),
                    cancelAffordance: cancelAffordance ?? .init(title: "Cancel request", isEnabled: true)
                ),
                summary: currentContextSummaryDisplayModel,
                selectedModel: selectedModelDisplayModel
            )
        case .completed, .failed, .cancelled, .persistenceRecovery:
            if let metadata = aiChatUnconnectedMetadata(for: self) {
                return .unconnected(connection: metadata, summary: currentContextSummaryDisplayModel)
            }
            if let metadata = aiChatTerminalErrorMetadata(for: self) {
                return .error(connection: metadata, summary: currentContextSummaryDisplayModel)
            }
            return .ready(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
        case .idle:
            break
        }

        switch connectionState {
        case let .unconnected(metadata):
            return .unconnected(connection: metadata, summary: currentContextSummaryDisplayModel)
        case let .error(metadata):
            return .error(connection: metadata, summary: currentContextSummaryDisplayModel)
        case .connected:
            if isInitialChatSurface {
                return .empty(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
            }

            return .ready(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
        }
    }

    public var modelFieldLabel: String { "Model" }

    public var isProcessing: Bool { executionPhase.isProcessing }

    public var resolvedSelectedModelHandle: AiModelHandle? {
        resolvedSelectedModel?.id
    }

    public var resolvedSelectedModel: AiProviderModel? {
        resolvedModel(for: selectedModelHandle)
    }

    private var chatInputModelLabel: String? {
        if let model = resolvedSelectedModel {
            return model.displayName
        }

        return modelListStatusLabel
    }

    private var chatInputThinkingLabel: String {
        if let model = resolvedSelectedModel {
            if let selectedThinking {
                return Self.thinkingLabel(for: selectedThinking)
            }

            return Self.defaultThinkingLabel(for: model.thinkingCapability)
        }

        return modelListStatusLabel
    }

    private var modelListStatusLabel: String {
        switch modelListState {
        case .idle, .loading:
            return "Loading models"
        case .empty:
            return "No models available"
        case let .failed(failure):
            return failure.message
        case .loaded:
            return "Select model"
        }
    }

    private func lockedModelDisplayModel(for lock: AiChatRequestLock) -> AiChatLockedModelDisplayModel {
        if let row = lock.selectedModelRow ?? resolvedModelRow(for: lock.selectedModelHandle) {
            return AiChatLockedModelDisplayModel(handle: row.handle, label: AiChatModelLabel(title: row.displayName))
        }

        return AiChatLockedModelDisplayModel(
            handle: lock.selectedModelHandle,
            label: AiChatModelLabel(title: lock.selectedModelHandle.rawValue)
        )
    }

    private var isInitialChatSurface: Bool {
        transcriptHistory.isEmpty
    }

    private func modelCatalogSections(
        rowsByHandle: [AiModelHandle: AiChatModelCatalogRowDisplayModel]
    ) -> [AiChatModelCatalogSectionDisplayModel] {
        guard case .loaded = modelListState else { return [] }

        let discoveredProviders = availableModels.reduce(into: [AiProvider]()) { providers, model in
            if !providers.contains(model.provider) {
                providers.append(model.provider)
            }
        }

        let groupedProviders: [AiProvider]
        switch providerConnectionSnapshot {
        case let .known(providers):
            groupedProviders = providers + discoveredProviders.filter { !providers.contains($0) }
        case .unknown:
            groupedProviders = discoveredProviders
        }

        return groupedProviders.compactMap { provider in
            let providerModels = availableModelsByProvider[provider] ?? availableModels.filter { $0.provider == provider }
            let providerRows = providerModels.compactMap { model in
                rowsByHandle[model.id]
            }
            guard !providerRows.isEmpty else { return nil }
            return AiChatModelCatalogSectionDisplayModel(
                provider: provider,
                title: aiChatProviderSectionTitle(for: provider),
                rows: providerRows
            )
        }
    }

    func normalizedSelectionHandle(
        _ preferredHandle: AiModelHandle?,
        in models: [AiProviderModel]? = nil
    ) -> AiModelHandle? {
        resolvedModel(for: preferredHandle, in: models)?.id
    }

    func normalizedSelectionHandlePreservingCurrentSelection(
        in models: [AiProviderModel],
        preferredHandle: AiModelHandle?
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

func aiChatTerminalErrorMetadata(for state: AiChatState) -> AiChatConnectionMetadata? {
    switch state.executionPhase {
    case .persistenceRecovery:
        if let failure = state.lastExecutionFailure {
            return aiChatExecutionFailureMetadata(for: failure)
        }
        return aiChatSessionStatusErrorMetadata(for: state)
    case .completed, .cancelled:
        return aiChatSessionStatusErrorMetadata(for: state)
    case .failed:
        return nil
    case .idle, .processing:
        return nil
    }
}

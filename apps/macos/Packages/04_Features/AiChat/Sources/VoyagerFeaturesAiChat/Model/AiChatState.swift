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

public enum AiChatMode: Equatable, Sendable {
    case sessions
    case chat
}

public struct AiChatSessionListState: Equatable, Sendable {
    public var allRows: [AiChatSessionSummary]
    public var rows: [AiChatSessionSummary]
    public var query: String
    public var isLoading: Bool
    public var errorMessage: String?
    public var selectedSessionID: AiChatSessionID?

    public init(
        allRows: [AiChatSessionSummary] = [],
        rows: [AiChatSessionSummary]? = nil,
        query: String = "",
        isLoading: Bool = false,
        errorMessage: String? = nil,
        selectedSessionID: AiChatSessionID? = nil
    ) {
        self.allRows = allRows
        self.query = query
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.selectedSessionID = selectedSessionID
        self.rows = rows ?? Self.filteredRows(from: allRows, query: query)
    }

    public mutating func setLoadedRows(_ rows: [AiChatSessionSummary]) {
        allRows = rows
        self.rows = Self.filteredRows(from: rows, query: query)
    }

    public mutating func updateQuery(_ query: String) {
        self.query = query
        rows = Self.filteredRows(from: allRows, query: query)
    }

    public mutating func removeRow(sessionID: AiChatSessionID) {
        allRows.removeAll { $0.sessionID == sessionID }
        rows = Self.filteredRows(from: allRows, query: query)
        if selectedSessionID == sessionID {
            selectedSessionID = nil
        }
    }

    static func filteredRows(from rows: [AiChatSessionSummary], query: String) -> [AiChatSessionSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return rows }
        let normalizedQuery = trimmedQuery.localizedLowercase
        return rows.filter { row in
            [row.title, row.preview, row.contextTitle]
                .compactMap { $0?.localizedLowercase }
                .contains { $0.contains(normalizedQuery) }
        }
    }
}

@ObservableState
public struct AiChatState: Equatable, Sendable {
    public var restoreSessionID: AiChatSessionID?
    public var restoreOutcome: AiChatSessionRestoreResult?
    public var restoreFailure: AiChatSessionRestoreFailure?
    public var mode: AiChatMode
    public var sessionList: AiChatSessionListState
    public var sessionID: AiChatSessionID?
    public var sessionStatus: AiChatSessionStatus
    public var currentContext: AiChatCurrentContextSnapshot
    public var addedAttachments: [AiChatAttachmentDraft]
    public var transcriptHistory: [AiChatMessage]
    public var draftText: String
    public var streamingAssistantDraft: String?
    public var catalogRows: [AiModelCatalogRow]
    public var modelListState: AiChatModelListState
    public var isModelSelectorPresented: Bool
    public var selectedModelHandle: AiModelHandle?
    public var selectedThinking: AiThinkingSelection?
    public var unavailableSelectedModelHandle: AiModelHandle?
    public var lockedModelHandle: AiModelHandle?
    public var lastExecutionFailure: AiChatExecutionFailure?
    public var lastRequestContext: AiChatLockedRequestContextSnapshot?
    public var lastRequestContextModelHandle: AiModelHandle?
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
        mode: AiChatMode = .sessions,
        sessionList: AiChatSessionListState = .init(),
        sessionID: AiChatSessionID? = nil,
        sessionStatus: AiChatSessionStatus = .idle,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        addedAttachments: [AiChatAttachmentDraft] = [],
        transcriptHistory: [AiChatMessage] = [],
        draftText: String = "",
        streamingAssistantDraft: String? = nil,
        catalogRows: [AiModelCatalogRow] = [],
        modelListState: AiChatModelListState? = nil,
        isModelSelectorPresented: Bool = false,
        selectedModelHandle: AiModelHandle? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        unavailableSelectedModelHandle: AiModelHandle? = nil,
        lockedModelHandle: AiModelHandle? = nil,
        lastExecutionFailure: AiChatExecutionFailure? = nil,
        lastRequestContext: AiChatLockedRequestContextSnapshot? = nil,
        lastRequestContextModelHandle: AiModelHandle? = nil,
        executionPhase: AiChatExecutionPhase = .idle,
        modelListRequestID: UUID? = nil,
        modelListProvider: AiProvider? = nil,
        modelListProviderOrder: [AiProvider] = [],
        modelListPendingProviders: Set<AiProvider> = [],
        modelListLoadedModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        modelListFailedProviders: [AiProvider: AiModelListFailure] = [:],
        providerConnectionSnapshot: AiChatProviderConnectionSnapshot = .unknown,
        availableModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
    ) {
        self.restoreSessionID = restoreSessionID
        self.restoreOutcome = restoreOutcome
        self.restoreFailure = restoreFailure
        self.mode = mode
        self.sessionList = sessionList
        self.sessionID = sessionID
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.transcriptHistory = transcriptHistory
        self.draftText = draftText
        self.streamingAssistantDraft = streamingAssistantDraft
        let resolvedModelListState = modelListState ?? Self.modelListState(from: catalogRows)
        self.catalogRows = catalogRows.isEmpty ? Self.makeCatalogRows(for: resolvedModelListState) : catalogRows
        self.modelListState = resolvedModelListState
        self.isModelSelectorPresented = isModelSelectorPresented
        self.selectedModelHandle = selectedModelHandle
        self.selectedThinking = selectedThinking
        self.unavailableSelectedModelHandle = unavailableSelectedModelHandle
        self.lockedModelHandle = lockedModelHandle
        self.lastExecutionFailure = lastExecutionFailure
        self.lastRequestContext = lastRequestContext
        self.lastRequestContextModelHandle = lastRequestContextModelHandle
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

    public var availableModels: [AiProviderModel] { displayModelBuilder.availableModels }
    public var currentContextSummaryDisplayModel: AiChatContextSummaryDisplayModel {
        displayModelBuilder.currentContextSummaryDisplayModel
    }

    public var connectionState: AiChatConnectionState { displayModelBuilder.connectionState }
    public var emptyStateDisplayModel: AiChatEmptyStateDisplayModel { displayModelBuilder.emptyStateDisplayModel }
    public var chatInputDisplayModel: AiChatInputDisplayModel { displayModelBuilder.chatInputDisplayModel }
    public var skeletonDisplayModel: AiChatSkeletonDisplayModel { displayModelBuilder.skeletonDisplayModel }
    public var skeletonSurfaceDisplayModel: AiChatSkeletonSurfaceDisplayModel {
        displayModelBuilder.skeletonSurfaceDisplayModel
    }

    public var streamingAssistantDisplayModel: AiChatStreamingAssistantDisplayModel? {
        displayModelBuilder.streamingAssistantDisplayModel
    }

    public var modelCatalogState: AiChatModelCatalogState { displayModelBuilder.modelCatalogState }
    public var modelSelectorContentState: AiChatModelSelectorContentState {
        displayModelBuilder.modelSelectorContentState
    }

    public var modelSelectorHasPresentableContent: Bool {
        displayModelBuilder.modelSelectorHasPresentableContent
    }

    public var modelSelectorIsDisabled: Bool { displayModelBuilder.modelSelectorIsDisabled }
    public var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        displayModelBuilder.selectedModelDisplayModel
    }

    public var lockedModelDisplayModel: AiChatLockedModelDisplayModel? { displayModelBuilder.lockedModelDisplayModel }
    public var canSubmit: Bool { displayModelBuilder.canSubmit }
    public var canRegenerate: Bool { displayModelBuilder.canRegenerate }
    public var requestStatusText: String? { displayModelBuilder.requestStatusText }
    public var sessionStatusText: String? { displayModelBuilder.sessionStatusText }
    public var cancelAffordance: AiChatCancelAffordance? { displayModelBuilder.cancelAffordance }
    public var surfaceState: AiChatSurfaceState { displayModelBuilder.surfaceState }
    public var modelFieldLabel: String { displayModelBuilder.modelFieldLabel }
    public var isProcessing: Bool { displayModelBuilder.isProcessing }
    public var resolvedSelectedModelHandle: AiModelHandle? { displayModelBuilder.resolvedSelectedModelHandle }
    public var resolvedSelectedModel: AiProviderModel? { displayModelBuilder.resolvedSelectedModel }

    private var displayModelBuilder: AiChatStateDisplayModelBuilder {
        AiChatStateDisplayModelBuilder(state: self)
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

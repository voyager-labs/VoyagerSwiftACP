import Foundation
import VoyagerEntitiesAi

struct AiChatStateDisplayModelBuilder {
    let state: AiChatState

    var availableModels: [AiProviderModel] {
        switch state.modelListState {
        case let .loaded(models):
            models
        case .idle, .loading, .empty, .failed:
            []
        }
    }

    var currentContextSummaryDisplayModel: AiChatContextSummaryDisplayModel {
        aiChatContextSummaryDisplayModel(for: state.currentContext)
    }

    var connectionState: AiChatConnectionState {
        if let metadata = aiChatUnconnectedMetadata(for: state) {
            return .unconnected(metadata)
        }
        if let metadata = aiChatErrorMetadata(for: state) {
            return .error(metadata)
        }
        return .connected
    }

    var emptyStateDisplayModel: AiChatEmptyStateDisplayModel {
        AiChatEmptyStateDisplayModel(
            title: "Ask about this context",
            detail: "Send a message to start a contextual chat."
        )
    }

    var chatInputDisplayModel: AiChatInputDisplayModel {
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

    var skeletonDisplayModel: AiChatSkeletonDisplayModel {
        AiChatSkeletonDisplayModel(
            headerTitle: "Chat",
            currentContext: currentContextSummaryDisplayModel,
            surface: skeletonSurfaceDisplayModel,
            chatInput: chatInputDisplayModel
        )
    }

    var skeletonSurfaceDisplayModel: AiChatSkeletonSurfaceDisplayModel {
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

    var streamingAssistantDisplayModel: AiChatStreamingAssistantDisplayModel? {
        guard let draft = state.streamingAssistantDraft,
              !draft.isEmpty
        else {
            return nil
        }

        switch state.executionPhase {
        case .processing:
            return AiChatStreamingAssistantDisplayModel(content: draft)
        case let .failed(lock, failure):
            guard lock.observabilitySummary.chunkCount > 0 else { return nil }
            return AiChatStreamingAssistantDisplayModel(content: draft, failure: failure)
        case .idle, .completed, .cancelled, .persistenceRecovery:
            return nil
        }
    }

    var modelCatalogState: AiChatModelCatalogState { modelCatalogBuilder.modelCatalogState }
    var modelSelectorContentState: AiChatModelSelectorContentState { modelCatalogBuilder.modelSelectorContentState }
    var modelSelectorHasPresentableContent: Bool { modelSelectorContentState.hasPresentableContent }
    var modelSelectorIsDisabled: Bool { modelCatalogBuilder.modelSelectorIsDisabled }
    var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? { modelCatalogBuilder.selectedModelDisplayModel }
    var lockedModelDisplayModel: AiChatLockedModelDisplayModel? { modelCatalogBuilder.lockedModelDisplayModel }

    private var modelCatalogBuilder: AiChatModelCatalogStateBuilder {
        AiChatModelCatalogStateBuilder(state: state, availableModels: availableModels)
    }

    var canSubmit: Bool {
        guard !state.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isProcessing else { return false }
        guard case .loaded = state.modelListState else { return false }
        guard resolvedSelectedModel != nil else { return false }
        guard selectedModelSupportsChatExecution else { return false }
        guard connectionState == .connected else { return false }

        switch surfaceState {
        case .empty, .ready:
            return true
        case .unconnected, .error, .processing:
            return false
        }
    }

    var canRegenerate: Bool {
        !isProcessing && state.transcriptHistory.contains(where: { $0.role == .assistant })
    }

    var requestStatusText: String? {
        switch state.executionPhase {
        case .idle:
            return selectedModelUnsupportedStatusText
        case let .processing(lock):
            return "Processing \(lock.selectedModelRow?.displayName ?? lock.selectedModelHandle.rawValue)"
        case .completed:
            return selectedModelUnsupportedStatusText
        case let .failed(_, failure):
            return failure.displayMessage
        case .cancelled:
            return "Request cancelled"
        case let .persistenceRecovery(_, failure):
            return "Finalized locally; \(failure.displayMessage)"
        }
    }

    var sessionStatusText: String? {
        if state.sessionStatus == .restoring { return "Restoring session" }
        switch state.restoreOutcome {
        case .restored:
            return "Restored session"
        case .newSession:
            return "Started new session"
        case .rebindRequired:
            return "Session needs rebind"
        case .failed, nil:
            return nil
        }
    }

    private var selectedModelSupportsChatExecution: Bool {
        guard let selectedModel = resolvedSelectedModel else { return false }
        return selectedModel.provider.supportsAiChatExecution
    }

    private var selectedModelUnsupportedStatusText: String? {
        guard let selectedModel = resolvedSelectedModel,
              !selectedModel.provider.supportsAiChatExecution
        else {
            return nil
        }
        return AiChatExecutionFailure.unsupportedProvider.displayMessage
    }

    var cancelAffordance: AiChatCancelAffordance? {
        guard state.executionPhase.isProcessing else { return nil }
        return AiChatCancelAffordance(title: "Cancel request", isEnabled: true)
    }

    var surfaceState: AiChatSurfaceState {
        switch state.executionPhase {
        case let .processing(lock):
            return .processing(
                processing: AiChatProcessingState(
                    lockedModel: modelCatalogBuilder.lockedModelDisplayModel(for: lock),
                    cancelAffordance: cancelAffordance ?? .init(title: "Cancel request", isEnabled: true)
                ),
                summary: currentContextSummaryDisplayModel,
                selectedModel: selectedModelDisplayModel
            )
        case .completed, .failed, .cancelled, .persistenceRecovery:
            if let metadata = aiChatUnconnectedMetadata(for: state) {
                return .unconnected(connection: metadata, summary: currentContextSummaryDisplayModel)
            }
            if let metadata = aiChatTerminalErrorMetadata(for: state) {
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

    var modelFieldLabel: String { "Model" }
    var isProcessing: Bool { state.executionPhase.isProcessing }
    var resolvedSelectedModelHandle: AiModelHandle? { resolvedSelectedModel?.id }
    var resolvedSelectedModel: AiProviderModel? { state.resolvedModel(for: state.selectedModelHandle) }

    private var chatInputModelLabel: String? {
        if let model = resolvedSelectedModel { return model.displayName }
        return modelListStatusLabel
    }

    private var chatInputThinkingLabel: String {
        if let model = resolvedSelectedModel {
            if let selectedThinking = state.selectedThinking {
                return AiChatStateSelection.thinkingLabel(for: selectedThinking)
            }
            return AiChatStateSelection.defaultThinkingLabel(for: model.thinkingCapability)
        }
        return modelListStatusLabel
    }

    private var modelListStatusLabel: String {
        switch state.modelListState {
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

    private var isInitialChatSurface: Bool { state.transcriptHistory.isEmpty }
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

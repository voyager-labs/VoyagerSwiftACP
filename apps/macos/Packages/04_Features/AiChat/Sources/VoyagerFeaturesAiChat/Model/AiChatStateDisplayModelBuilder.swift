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

    var requestContextDisplayModel: AiChatRequestContextDisplayModel {
        aiChatRequestContextDisplayModel(
            currentContext: state.currentContext,
            addedAttachments: state.addedAttachments,
            lockedRequestContext: lockedRequestContextSnapshot,
        )
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
            detail: "Send a message to start a contextual chat.",
        )
    }

    var chatInputDisplayModel: AiChatInputDisplayModel {
        let showsStop = hasVisiblePendingRequest || isVisibleRequestProcessing
        let stopEnabled = hasVisiblePendingRequest
            || (isVisibleRequestProcessing && (cancelAffordance?.isEnabled ?? false))
        let submitHelp = "Enter to send, Shift+Enter for new line"
        return AiChatInputDisplayModel(
            placeholder: "Ask anything…",
            inputAccessibilityLabel: "Chat message",
            inputAccessibilityHint: submitHelp,
            contextAffordanceLabel: "+",
            modelLabel: chatInputModelLabel,
            effortLabel: chatInputThinkingLabel,
            submitAccessibilityLabel: "Send",
            stopAccessibilityLabel: "Stop",
            submitHelp: submitHelp,
            stopHelp: "Stop generating response",
            isSubmitVisible: !showsStop,
            isStopVisible: showsStop,
            canSubmit: canSubmit,
            canStop: stopEnabled,
            isComposerEditingDisabled: hasVisiblePendingRequest,
        )
    }

    var skeletonDisplayModel: AiChatSkeletonDisplayModel {
        AiChatSkeletonDisplayModel(
            headerTitle: "Chat",
            currentContext: currentContextSummaryDisplayModel,
            surface: skeletonSurfaceDisplayModel,
            chatInput: chatInputDisplayModel,
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
        switch state.executionPhase {
        case let .processing(lock):
            guard isVisibleRequest(lock: lock) else { return nil }
            return streamingAssistantDisplayModel(lock: lock)
        case let .failed(lock, failure):
            guard isVisibleRequest(lock: lock) else { return nil }
            return streamingAssistantDisplayModel(lock: lock, failure: failure)
        case .idle, .completed, .cancelled, .persistenceRecovery:
            return nil
        }
    }

    private func streamingAssistantDisplayModel(
        lock: AiChatRequestLock,
        failure: AiChatExecutionFailure? = nil,
    ) -> AiChatStreamingAssistantDisplayModel {
        let content = nonEmptyStreamingContent
        return AiChatStreamingAssistantDisplayModel(
            requestID: lock.requestID,
            content: content,
            title: modelCatalogBuilder.lockedModelDisplayModel(for: lock).title,
            thinkingLabel: lock.context.selectedThinking.map(AiChatStateSelection.thinkingLabel(for:)),
            acceptedChunkRevision: lock.observabilitySummary.chunkCount,
            failure: failure,
            activityStatusLabel: activityStatusLabel(
                lock: lock,
                hasContent: content != nil,
                isProcessing: failure == nil,
            ),
        )
    }

    private func activityStatusLabel(
        lock: AiChatRequestLock,
        hasContent: Bool,
        isProcessing: Bool,
    ) -> String? {
        guard isProcessing else { return nil }
        if let activity = lock.activityState.selectedActivity {
            return activity.kind.aiChatStatusLabel
        }
        return hasContent ? nil : "Waiting for response…"
    }

    private var nonEmptyStreamingContent: String? {
        guard let draft = state.streamingAssistantDraft,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return draft
    }

    var modelCatalogState: AiChatModelCatalogState {
        modelCatalogBuilder.modelCatalogState
    }

    var modelSelectorContentState: AiChatModelSelectorContentState {
        modelCatalogBuilder.modelSelectorContentState
    }

    var modelSelectorHasPresentableContent: Bool {
        modelSelectorContentState.hasPresentableContent
    }

    var modelSelectorIsDisabled: Bool {
        hasVisiblePendingRequest || modelCatalogBuilder.modelSelectorIsDisabled
    }

    var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        modelCatalogBuilder.selectedModelDisplayModel
    }

    var thinkingMenuItems: [AiChatThinkingMenuItemDisplayModel] {
        guard let model = resolvedSelectedModel else { return [] }

        switch model.thinkingCapability {
        case let .unsupported(reason), let .unknown(reason):
            return [thinkingUnavailableMenuItem(reason: reason.message)]
        case .effort, .adaptive, .tokenBudget:
            let options = AiThinkingSelectionPolicy.options(
                capability: model.thinkingCapability,
                supportsNone: model.supportsThinkingNone,
            )
            guard !options.isEmpty else {
                return [thinkingUnavailableMenuItem(reason: "Thinking token budget metadata is invalid.")]
            }
            return options.map { option in
                let isSelected = option.selection == state.selectedThinking
                return AiChatThinkingMenuItemDisplayModel(
                    selection: option.selection,
                    title: option.title,
                    isSelected: isSelected,
                    isEnabled: true,
                    disabledReason: nil,
                    accessibilityLabel: option.title,
                    accessibilityValue: isSelected ? "Selected" : "Not selected",
                )
            }
        }
    }

    var thinkingMenuIsDisabled: Bool {
        resolvedSelectedModel == nil
    }

    private func thinkingUnavailableMenuItem(reason: String) -> AiChatThinkingMenuItemDisplayModel {
        AiChatThinkingMenuItemDisplayModel(
            selection: nil,
            title: "Thinking unavailable",
            isSelected: false,
            isEnabled: false,
            disabledReason: reason,
            accessibilityLabel: "Thinking unavailable",
            accessibilityValue: "Unavailable: \(reason)",
        )
    }

    var lockedModelDisplayModel: AiChatLockedModelDisplayModel? {
        modelCatalogBuilder.lockedModelDisplayModel
    }

    private var modelCatalogBuilder: AiChatModelCatalogStateBuilder {
        AiChatModelCatalogStateBuilder(state: state, availableModels: availableModels)
    }

    private var lockedRequestContextSnapshot: AiChatLockedRequestContextSnapshot? {
        visibleProcessingLock?.context.requestContext
    }

    var canSubmit: Bool {
        guard state.sessionStatus != .rebindRequired else { return false }
        guard !state.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !hasInFlightRequest else { return false }
        guard state.pendingRequestStart == nil else { return false }
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
        !hasInFlightRequest
            && resolvedSelectedModel != nil
            && state.transcriptHistory.contains(where: { $0.role == .assistant })
    }

    var requestStatusText: String? {
        switch state.executionPhase {
        case .idle:
            return selectedModelUnsupportedStatusText
        case let .processing(lock):
            guard isVisibleRequest(lock: lock) else { return selectedModelUnsupportedStatusText }
            return "Processing \(lock.selectedModelRow?.displayName ?? lock.selectedModelHandle.rawValue)"
        case .completed:
            return selectedModelUnsupportedStatusText
        case let .failed(lock, failure):
            guard isVisibleRequest(lock: lock) else { return selectedModelUnsupportedStatusText }
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
        guard isVisibleRequestProcessing else { return nil }
        return AiChatCancelAffordance(title: "Cancel request", isEnabled: true)
    }

    var surfaceState: AiChatSurfaceState {
        switch state.executionPhase {
        case let .processing(lock):
            if isVisibleRequest(lock: lock) {
                return .processing(
                    processing: AiChatProcessingState(
                        lockedModel: modelCatalogBuilder.lockedModelDisplayModel(for: lock),
                        cancelAffordance: cancelAffordance ?? .init(title: "Cancel request", isEnabled: true),
                    ),
                    summary: currentContextSummaryDisplayModel,
                    selectedModel: selectedModelDisplayModel,
                )
            }
        case let .failed(lock, _):
            if isVisibleRequest(lock: lock) {
                if let metadata = aiChatUnconnectedMetadata(for: state) {
                    return .unconnected(connection: metadata, summary: currentContextSummaryDisplayModel)
                }
                if let metadata = aiChatTerminalErrorMetadata(for: state) {
                    return .error(connection: metadata, summary: currentContextSummaryDisplayModel)
                }
                return .ready(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
            }
        case .completed, .cancelled, .persistenceRecovery:
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

    var modelFieldLabel: String {
        "Model"
    }

    var isProcessing: Bool {
        isVisibleRequestProcessing
    }

    var resolvedSelectedModelHandle: AiModelHandle? {
        resolvedSelectedModel?.id
    }

    var resolvedSelectedModel: AiProviderModel? {
        state.resolvedModel(for: state.selectedModelHandle)
    }

    private var visibleProcessingLock: AiChatRequestLock? {
        guard case let .processing(lock) = state.executionPhase,
              isVisibleRequest(lock: lock)
        else { return nil }
        return lock
    }

    private var isVisibleRequestProcessing: Bool {
        visibleProcessingLock != nil
    }

    private var hasVisiblePendingRequest: Bool {
        state.visiblePendingRequestStart != nil
    }

    private var hasInFlightRequest: Bool {
        if isVisibleRequestProcessing { return true }
        guard let sessionID = state.sessionID else { return false }
        if state.backgroundPendingRequestStarts.values.contains(where: { $0.sessionID == sessionID }) {
            return true
        }
        return state.backgroundExecutionPhases.values.contains { phase in
            phase.lock?.context.sessionID == sessionID
        }
    }

    private func isVisibleRequest(lock: AiChatRequestLock) -> Bool {
        guard let sessionID = state.sessionID else { return false }
        return lock.context.sessionID == sessionID
    }

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
            "Loading models"
        case .empty:
            "No models available"
        case let .failed(failure):
            failure.message
        case .loaded:
            "Select model"
        }
    }

    private var isInitialChatSurface: Bool {
        state.transcriptHistory.isEmpty
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

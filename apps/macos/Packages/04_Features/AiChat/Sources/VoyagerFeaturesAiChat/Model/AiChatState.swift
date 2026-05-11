import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

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
    public var streamDraftText: String
    public var catalogRows: [AiModelCatalogRow]
    public var selectedModelHandle: AiModelHandle?
    public var lockedModelHandle: AiModelHandle?
    public var lastExecutionFailure: AiChatExecutionFailure?
    public var executionPhase: AiChatExecutionPhase

    public init(
        restoreSessionID: AiChatSessionID? = nil,
        restoreOutcome: AiChatSessionRestoreResult? = nil,
        restoreFailure: AiChatSessionRestoreFailure? = nil,
        sessionID: AiChatSessionID? = nil,
        sessionStatus: AiChatSessionStatus = .idle,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        transcriptHistory: [AiChatMessage] = [],
        draftText: String = "",
        streamDraftText: String = "",
        catalogRows: [AiModelCatalogRow] = [],
        selectedModelHandle: AiModelHandle? = nil,
        lockedModelHandle: AiModelHandle? = nil,
        lastExecutionFailure: AiChatExecutionFailure? = nil,
        executionPhase: AiChatExecutionPhase = .idle
    ) {
        self.restoreSessionID = restoreSessionID
        self.restoreOutcome = restoreOutcome
        self.restoreFailure = restoreFailure
        self.sessionID = sessionID
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.transcriptHistory = transcriptHistory
        self.draftText = draftText
        self.streamDraftText = streamDraftText
        self.catalogRows = catalogRows
        self.selectedModelHandle = selectedModelHandle
        self.lockedModelHandle = lockedModelHandle
        self.lastExecutionFailure = lastExecutionFailure
        self.executionPhase = executionPhase
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
            effortLabel: "xhigh",
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

        return AiChatModelCatalogState(
            fieldLabel: "Model",
            rows: catalogRows.map { row in
                AiChatModelCatalogRowDisplayModel(
                    handle: row.handle,
                    label: aiChatModelLabel(for: row),
                    isSelected: row.handle == selectedHandle,
                    isLocked: row.handle == lockedHandle,
                    isDefault: row.isDefault,
                    isRecommended: row.isRecommended
                )
            },
            selectedModel: selectedModel,
            lockedModel: lockedModel
        )
    }

    public var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        guard let row = resolvedSelectedModelRow else { return nil }
        return AiChatSelectedModelDisplayModel(handle: row.handle, label: aiChatModelLabel(for: row))
    }

    public var lockedModelDisplayModel: AiChatLockedModelDisplayModel? {
        if case let .processing(lock) = executionPhase {
            return lockedModelDisplayModel(for: lock)
        }

        guard let handle = lockedModelHandle,
              let row = catalogRows.first(where: { $0.handle == handle })
        else { return nil }
        return AiChatLockedModelDisplayModel(handle: row.handle, label: aiChatModelLabel(for: row))
    }

    public var canSubmit: Bool {
        guard !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isProcessing else { return false }
        guard resolvedSelectedModelRow != nil else { return false }
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

    private var chatInputModelLabel: String? {
        selectedModelDisplayModel?.label.title
            ?? lockedModelDisplayModel?.label.title
    }

    private func lockedModelDisplayModel(for lock: AiChatRequestLock) -> AiChatLockedModelDisplayModel {
        if let row = lock.selectedModelRow ?? catalogRows.first(where: { $0.handle == lock.selectedModelHandle }) {
            return AiChatLockedModelDisplayModel(handle: row.handle, label: aiChatModelLabel(for: row))
        }

        return AiChatLockedModelDisplayModel(
            handle: lock.selectedModelHandle,
            label: AiChatModelLabel(title: lock.selectedModelHandle.rawValue)
        )
    }

    private var isInitialChatSurface: Bool {
        transcriptHistory.isEmpty
            && streamDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedSelectedModelRow: AiModelCatalogRow? {
        if let handle = selectedModelHandle,
           let row = catalogRows.first(where: { $0.handle == handle }) {
            return row
        }

        guard !catalogRows.isEmpty else { return nil }
        return catalogRows.first
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

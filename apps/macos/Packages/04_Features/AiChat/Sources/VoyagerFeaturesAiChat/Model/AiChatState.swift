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
        if let metadata = aiChatConnectionMetadata(for: self) {
            if sessionID == nil {
                return .unconnected(metadata)
            }
            return .error(metadata)
        }
        return sessionID == nil ? .unconnected(.init(
            title: "No session connected",
            detail: "Start or open a session to continue from the current context.",
            fixLabel: "Open session"
        )) : .connected
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
        guard let handle = lockedModelHandle,
              let row = catalogRows.first(where: { $0.handle == handle })
        else { return nil }
        return AiChatLockedModelDisplayModel(handle: row.handle, label: aiChatModelLabel(for: row))
    }

    public var canSubmit: Bool {
        !isProcessing && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard lockedModelDisplayModel != nil else { return nil }
        return AiChatCancelAffordance(title: "Cancel request", isEnabled: true)
    }

    public var surfaceState: AiChatSurfaceState {
        switch connectionState {
        case let .unconnected(metadata):
            return .unconnected(connection: metadata, summary: currentContextSummaryDisplayModel)
        case let .error(metadata):
            return .error(connection: metadata, summary: currentContextSummaryDisplayModel)
        case .connected:
            if let lockedModel = lockedModelDisplayModel {
                return .processing(
                    processing: AiChatProcessingState(
                        lockedModel: lockedModel,
                        cancelAffordance: cancelAffordance ?? .init(title: "Cancel request", isEnabled: true)
                    ),
                    summary: currentContextSummaryDisplayModel,
                    selectedModel: selectedModelDisplayModel
                )
            }

            if currentContextSummaryDisplayModel.isEmpty, transcriptHistory.isEmpty, draftText.isEmpty {
                return .empty(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
            }

            return .ready(summary: currentContextSummaryDisplayModel, selectedModel: selectedModelDisplayModel)
        }
    }

    public var modelFieldLabel: String { "Model" }

    public var isProcessing: Bool { lockedModelDisplayModel != nil }

    private var resolvedSelectedModelRow: AiModelCatalogRow? {
        if let handle = selectedModelHandle,
           let row = catalogRows.first(where: { $0.handle == handle })
        {
            return row
        }

        guard !catalogRows.isEmpty else { return nil }
        return catalogRows.first
    }
}

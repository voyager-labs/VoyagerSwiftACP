import Foundation
import VoyagerEntitiesAi

public struct AiChatConnectionMetadata: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var fixLabel: String

    public init(title: String, detail: String, fixLabel: String) {
        self.title = title
        self.detail = detail
        self.fixLabel = fixLabel
    }
}

public enum AiChatConnectionState: Equatable, Sendable {
    case unconnected(AiChatConnectionMetadata)
    case error(AiChatConnectionMetadata)
    case connected
}

public struct AiChatContextSummaryDisplayModel: Equatable, Sendable {
    public var title: String
    public var detail: String?
    public var referenceCount: Int
    public var itemCount: Int
    public var attachmentCount: Int
    public var isEmpty: Bool

    public init(
        title: String,
        detail: String? = nil,
        referenceCount: Int,
        itemCount: Int,
        attachmentCount: Int,
        isEmpty: Bool
    ) {
        self.title = title
        self.detail = detail
        self.referenceCount = referenceCount
        self.itemCount = itemCount
        self.attachmentCount = attachmentCount
        self.isEmpty = isEmpty
    }
}

public struct AiChatModelLabel: Equatable, Sendable {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct AiChatSelectedModelDisplayModel: Equatable, Sendable {
    public var handle: AiModelHandle
    public var label: AiChatModelLabel

    public init(handle: AiModelHandle, label: AiChatModelLabel) {
        self.handle = handle
        self.label = label
    }
}

public struct AiChatLockedModelDisplayModel: Equatable, Sendable {
    public var handle: AiModelHandle
    public var label: AiChatModelLabel

    public init(handle: AiModelHandle, label: AiChatModelLabel) {
        self.handle = handle
        self.label = label
    }
}

public struct AiChatCancelAffordance: Equatable, Sendable {
    public var title: String
    public var isEnabled: Bool

    public init(title: String, isEnabled: Bool) {
        self.title = title
        self.isEnabled = isEnabled
    }
}

public struct AiChatProcessingState: Equatable, Sendable {
    public var lockedModel: AiChatLockedModelDisplayModel
    public var cancelAffordance: AiChatCancelAffordance

    public init(lockedModel: AiChatLockedModelDisplayModel, cancelAffordance: AiChatCancelAffordance) {
        self.lockedModel = lockedModel
        self.cancelAffordance = cancelAffordance
    }
}

public struct AiChatModelCatalogRowDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiModelHandle { handle }

    public var handle: AiModelHandle
    public var label: AiChatModelLabel
    public var isSelected: Bool
    public var isLocked: Bool
    public var isDefault: Bool
    public var isRecommended: Bool

    public init(
        handle: AiModelHandle,
        label: AiChatModelLabel,
        isSelected: Bool,
        isLocked: Bool,
        isDefault: Bool,
        isRecommended: Bool
    ) {
        self.handle = handle
        self.label = label
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.isDefault = isDefault
        self.isRecommended = isRecommended
    }
}

public struct AiChatModelCatalogState: Equatable, Sendable {
    public var fieldLabel: String
    public var rows: [AiChatModelCatalogRowDisplayModel]
    public var selectedModel: AiChatSelectedModelDisplayModel?
    public var lockedModel: AiChatLockedModelDisplayModel?

    public init(
        fieldLabel: String,
        rows: [AiChatModelCatalogRowDisplayModel],
        selectedModel: AiChatSelectedModelDisplayModel?,
        lockedModel: AiChatLockedModelDisplayModel?
    ) {
        self.fieldLabel = fieldLabel
        self.rows = rows
        self.selectedModel = selectedModel
        self.lockedModel = lockedModel
    }
}

public enum AiChatSurfaceState: Equatable, Sendable {
    case unconnected(connection: AiChatConnectionMetadata, summary: AiChatContextSummaryDisplayModel)
    case error(connection: AiChatConnectionMetadata, summary: AiChatContextSummaryDisplayModel)
    case empty(summary: AiChatContextSummaryDisplayModel, selectedModel: AiChatSelectedModelDisplayModel?)
    case ready(summary: AiChatContextSummaryDisplayModel, selectedModel: AiChatSelectedModelDisplayModel?)
    case processing(processing: AiChatProcessingState, summary: AiChatContextSummaryDisplayModel, selectedModel: AiChatSelectedModelDisplayModel?)
}

func aiChatModelLabel(for row: AiModelCatalogRow) -> AiChatModelLabel {
    let providerLabel = ProviderDescriptor.descriptor(for: row.handle.provider)?.displayName ?? row.handle.provider.rawValue
    return AiChatModelLabel(title: row.displayName, subtitle: row.subtitle ?? providerLabel)
}

func aiChatContextSummaryDisplayModel(for snapshot: AiChatCurrentContextSnapshot) -> AiChatContextSummaryDisplayModel {
    let referenceCount = snapshot.references.count
    let itemCount = snapshot.items.count
    let attachmentCount = snapshot.attachments.count
    let hasContent = referenceCount > 0 || itemCount > 0 || attachmentCount > 0
    let trimmedSummary = snapshot.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmedSummary.flatMap { $0.isEmpty ? nil : $0 } ?? (hasContent ? "Current context" : "No current context")
    let detailParts = [
        referenceCount > 0 ? "\(referenceCount) \(referenceCount == 1 ? "reference" : "references")" : nil,
        itemCount > 0 ? "\(itemCount) \(itemCount == 1 ? "item" : "items")" : nil,
        attachmentCount > 0 ? "\(attachmentCount) \(attachmentCount == 1 ? "attachment" : "attachments")" : nil,
    ].compactMap { $0 }
    return AiChatContextSummaryDisplayModel(
        title: title,
        detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
        referenceCount: referenceCount,
        itemCount: itemCount,
        attachmentCount: attachmentCount,
        isEmpty: !hasContent && (trimmedSummary?.isEmpty ?? true)
    )
}

func aiChatConnectionMetadata(for state: AiChatState) -> AiChatConnectionMetadata? {
    if state.sessionID == nil {
        return AiChatConnectionMetadata(
            title: "No session connected",
            detail: "Start or open a session to continue from the current context.",
            fixLabel: "Open session"
        )
    }

    if state.catalogRows.isEmpty || state.selectedModelDisplayModel == nil {
        return AiChatConnectionMetadata(
            title: "No AI provider connected",
            detail: "Connect an AI provider in Settings to start chatting.",
            fixLabel: "Connect provider in Settings"
        )
    }

    if let failure = state.lastExecutionFailure {
        return AiChatConnectionMetadata(
            title: "Chat unavailable",
            detail: failure.displayMessage,
            fixLabel: "Retry"
        )
    }

    switch state.sessionStatus {
    case .failed:
        return AiChatConnectionMetadata(
            title: "Session failed",
            detail: "The current chat session could not be loaded.",
            fixLabel: "Retry"
        )
    case .rebindRequired:
        return AiChatConnectionMetadata(
            title: "Session needs rebind",
            detail: "Reconnect the session before continuing.",
            fixLabel: "Reconnect"
        )
    default:
        return nil
    }
}

extension AiChatExecutionFailure {
    var displayMessage: String {
        switch self {
        case .cancelled:
            "The request was cancelled."
        case .transportError:
            "The chat service is temporarily unavailable."
        case .unsupportedProvider:
            "This provider is not supported for chat."
        case .sessionMismatch:
            "The current session no longer matches the active request."
        case .unknown:
            "An unknown chat error occurred."
        }
    }
}

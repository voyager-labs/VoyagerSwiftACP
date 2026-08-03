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
        detail: String?,
        referenceCount: Int,
        itemCount: Int,
        attachmentCount: Int,
        isEmpty: Bool,
    ) {
        self.title = title
        self.detail = detail
        self.referenceCount = referenceCount
        self.itemCount = itemCount
        self.attachmentCount = attachmentCount
        self.isEmpty = isEmpty
    }
}

public struct AiChatEmptyStateDisplayModel: Equatable, Sendable {
    public var title: String
    public var detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct AiChatInputDisplayModel: Equatable, Sendable {
    public var placeholder: String
    public var inputAccessibilityLabel: String
    public var inputAccessibilityHint: String
    public var contextAffordanceLabel: String
    public var modelLabel: String?
    public var effortLabel: String
    public var submitAccessibilityLabel: String
    public var stopAccessibilityLabel: String
    public var submitHelp: String
    public var stopHelp: String
    public var isSubmitVisible: Bool
    public var isStopVisible: Bool
    public var canSubmit: Bool
    public var canStop: Bool

    public init(
        placeholder: String,
        inputAccessibilityLabel: String,
        inputAccessibilityHint: String,
        contextAffordanceLabel: String,
        modelLabel: String?,
        effortLabel: String,
        submitAccessibilityLabel: String,
        stopAccessibilityLabel: String,
        submitHelp: String,
        stopHelp: String,
        isSubmitVisible: Bool,
        isStopVisible: Bool,
        canSubmit: Bool,
        canStop: Bool,
    ) {
        self.placeholder = placeholder
        self.inputAccessibilityLabel = inputAccessibilityLabel
        self.inputAccessibilityHint = inputAccessibilityHint
        self.contextAffordanceLabel = contextAffordanceLabel
        self.modelLabel = modelLabel
        self.effortLabel = effortLabel
        self.submitAccessibilityLabel = submitAccessibilityLabel
        self.stopAccessibilityLabel = stopAccessibilityLabel
        self.submitHelp = submitHelp
        self.stopHelp = stopHelp
        self.isSubmitVisible = isSubmitVisible
        self.isStopVisible = isStopVisible
        self.canSubmit = canSubmit
        self.canStop = canStop
    }

    public var actionHelp: String {
        isStopVisible ? stopHelp : submitHelp
    }
}

public enum AiChatSkeletonSurfaceDisplayModel: Equatable, Sendable {
    case unconnected(AiChatConnectionMetadata)
    case error(AiChatConnectionMetadata)
    case empty(AiChatEmptyStateDisplayModel)
    case ready
    case processing(AiChatProcessingState)
}

public struct AiChatSkeletonDisplayModel: Equatable, Sendable {
    public var headerTitle: String
    public var currentContext: AiChatContextSummaryDisplayModel
    public var surface: AiChatSkeletonSurfaceDisplayModel
    public var chatInput: AiChatInputDisplayModel

    public init(
        headerTitle: String,
        currentContext: AiChatContextSummaryDisplayModel,
        surface: AiChatSkeletonSurfaceDisplayModel,
        chatInput: AiChatInputDisplayModel,
    ) {
        self.headerTitle = headerTitle
        self.currentContext = currentContext
        self.surface = surface
        self.chatInput = chatInput
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

    public var title: String {
        label.title
    }

    public init(handle: AiModelHandle, label: AiChatModelLabel) {
        self.handle = handle
        self.label = label
    }
}

public struct AiChatLockedModelDisplayModel: Equatable, Sendable {
    public var handle: AiModelHandle
    public var label: AiChatModelLabel

    public var title: String {
        label.title
    }

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

public struct AiChatStreamingAssistantDisplayModel: Equatable, Sendable {
    public var content: String
    public var failure: AiChatExecutionFailure?

    public init(content: String, failure: AiChatExecutionFailure? = nil) {
        self.content = content
        self.failure = failure
    }
}

public struct AiChatModelCatalogRowDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiModelHandle {
        handle
    }

    public var handle: AiModelHandle
    public var label: AiChatModelLabel
    public var providerBadge: String?
    public var isSelected: Bool
    public var isLocked: Bool
    public var isDefault: Bool
    public var isRecommended: Bool
    var isEnabled: Bool
    var disabledReason: String?
    var accessibilityLabel: String
    var accessibilityValue: String

    public var title: String {
        label.title
    }

    public init(
        handle: AiModelHandle,
        label: AiChatModelLabel,
        providerBadge: String?,
        isSelected: Bool,
        isLocked: Bool,
        isDefault: Bool,
        isRecommended: Bool,
    ) {
        self.init(
            handle: handle,
            label: label,
            providerBadge: providerBadge,
            isSelected: isSelected,
            isLocked: isLocked,
            isDefault: isDefault,
            isRecommended: isRecommended,
            isEnabled: true,
            disabledReason: nil,
            accessibilityLabel: label.title,
            accessibilityValue: isSelected ? "Selected" : "Not selected",
        )
    }

    init(
        handle: AiModelHandle,
        label: AiChatModelLabel,
        providerBadge: String?,
        isSelected: Bool,
        isLocked: Bool,
        isDefault: Bool,
        isRecommended: Bool,
        isEnabled: Bool,
        disabledReason: String?,
        accessibilityLabel: String,
        accessibilityValue: String,
    ) {
        self.handle = handle
        self.label = label
        self.providerBadge = providerBadge
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.isDefault = isDefault
        self.isRecommended = isRecommended
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

struct AiChatThinkingMenuItemDisplayModel: Identifiable, Equatable {
    var id: AiThinkingSelection? {
        selection
    }

    var selection: AiThinkingSelection?
    var title: String
    var isSelected: Bool
    var isEnabled: Bool
    var disabledReason: String?
    var accessibilityLabel: String
    var accessibilityValue: String
}

public struct AiChatModelCatalogSectionDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiProvider {
        provider
    }

    public var provider: AiProvider
    public var title: String
    public var rows: [AiChatModelCatalogRowDisplayModel]

    public init(
        provider: AiProvider,
        title: String,
        rows: [AiChatModelCatalogRowDisplayModel],
    ) {
        self.provider = provider
        self.title = title
        self.rows = rows
    }
}

public struct AiChatModelCatalogState: Equatable, Sendable {
    public var fieldLabel: String
    public var rows: [AiChatModelCatalogRowDisplayModel]
    public var sections: [AiChatModelCatalogSectionDisplayModel]
    public var selectedModel: AiChatSelectedModelDisplayModel?
    public var lockedModel: AiChatLockedModelDisplayModel?

    public init(
        fieldLabel: String,
        rows: [AiChatModelCatalogRowDisplayModel],
        sections: [AiChatModelCatalogSectionDisplayModel],
        selectedModel: AiChatSelectedModelDisplayModel?,
        lockedModel: AiChatLockedModelDisplayModel?,
    ) {
        self.fieldLabel = fieldLabel
        self.rows = rows
        self.sections = sections
        self.selectedModel = selectedModel
        self.lockedModel = lockedModel
    }

    public init(
        fieldLabel: String,
        rows: [AiChatModelCatalogRowDisplayModel],
        selectedModel: AiChatSelectedModelDisplayModel?,
        lockedModel: AiChatLockedModelDisplayModel?,
    ) {
        self.init(
            fieldLabel: fieldLabel,
            rows: rows,
            sections: [],
            selectedModel: selectedModel,
            lockedModel: lockedModel,
        )
    }
}

public struct AiChatModelSelectorStatusDisplayModel: Equatable, Sendable {
    public var title: String
    public var detail: String

    var isEnabled: Bool {
        false
    }

    var isSelected: Bool {
        false
    }

    var disabledReason: String {
        detail
    }

    var accessibilityLabel: String {
        title
    }

    var accessibilityValue: String {
        detail
    }

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public enum AiChatModelSelectorContentState: Equatable, Sendable {
    case loading(AiChatModelSelectorStatusDisplayModel)
    case empty(AiChatModelSelectorStatusDisplayModel)
    case failed(AiChatModelSelectorStatusDisplayModel)
    case unsupported(AiChatModelSelectorStatusDisplayModel)
    case loaded([AiChatModelCatalogSectionDisplayModel])

    public var hasPresentableContent: Bool {
        switch self {
        case .loading, .empty, .failed, .unsupported:
            true
        case let .loaded(sections):
            !sections.isEmpty
        }
    }
}

public enum AiChatSurfaceState: Equatable, Sendable {
    case unconnected(connection: AiChatConnectionMetadata, summary: AiChatContextSummaryDisplayModel)
    case error(connection: AiChatConnectionMetadata, summary: AiChatContextSummaryDisplayModel)
    case empty(summary: AiChatContextSummaryDisplayModel, selectedModel: AiChatSelectedModelDisplayModel?)
    case ready(summary: AiChatContextSummaryDisplayModel, selectedModel: AiChatSelectedModelDisplayModel?)
    case processing(
        processing: AiChatProcessingState,
        summary: AiChatContextSummaryDisplayModel,
        selectedModel: AiChatSelectedModelDisplayModel?,
    )
}

func aiChatModelLabel(for row: AiModelCatalogRow) -> AiChatModelLabel {
    AiChatModelLabel(title: row.displayName, subtitle: row.subtitle)
}

func aiChatModelLabel(for model: AiProviderModel) -> AiChatModelLabel {
    AiChatModelLabel(title: model.displayName, subtitle: model.providerDisplayName)
}

func aiChatProviderSectionTitle(for provider: AiProvider) -> String {
    ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue
}

func aiChatContextSummaryDisplayModel(for snapshot: AiChatCurrentContextSnapshot) -> AiChatContextSummaryDisplayModel {
    let referenceCount = snapshot.references.count
    let itemCount = snapshot.items.count
    let attachmentCount = snapshot.attachments.count
    let hasContent = referenceCount > 0 || itemCount > 0 || attachmentCount > 0
    let trimmedSummary = snapshot.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmedSummary.flatMap { $0.isEmpty ? nil : $0 }
        ?? (hasContent ? "Current context" : "No current selection")
    let detailParts = [
        referenceCount > 0 ? "\(referenceCount) \(referenceCount == 1 ? "reference" : "references")" : nil,
        itemCount > 0 ? "\(itemCount) \(itemCount == 1 ? "item" : "items")" : nil,
        attachmentCount > 0 ? "\(attachmentCount) \(attachmentCount == 1 ? "attachment" : "attachments")" : nil,
    ].compactMap(\.self)
    return AiChatContextSummaryDisplayModel(
        title: title,
        detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
        referenceCount: referenceCount,
        itemCount: itemCount,
        attachmentCount: attachmentCount,
        isEmpty: !hasContent && (trimmedSummary?.isEmpty ?? true),
    )
}

func aiChatUnconnectedMetadata(for state: AiChatState) -> AiChatConnectionMetadata? {
    let isUnconnected = switch state.providerConnectionSnapshot {
    case let .known(providers):
        providers.isEmpty
    case .unknown:
        state.sessionID == nil
    }

    guard isUnconnected else {
        return nil
    }

    return AiChatConnectionMetadata(
        title: "Connect an AI provider",
        detail: "Set up a provider in Settings to chat with this context.",
        fixLabel: "Open Settings",
    )
}

func aiChatErrorMetadata(for state: AiChatState) -> AiChatConnectionMetadata? {
    if let failure = state.lastExecutionFailure {
        return aiChatExecutionFailureMetadata(for: failure)
    }

    return aiChatSessionStatusErrorMetadata(for: state)
}

func aiChatExecutionFailureMetadata(for failure: AiChatExecutionFailure) -> AiChatConnectionMetadata {
    AiChatConnectionMetadata(
        title: "Chat unavailable",
        detail: failure.displayMessage,
        fixLabel: "Retry",
    )
}

func aiChatSessionStatusErrorMetadata(for _: AiChatState) -> AiChatConnectionMetadata? {
    nil
}

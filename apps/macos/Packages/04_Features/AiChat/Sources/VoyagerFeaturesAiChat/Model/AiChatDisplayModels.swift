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
    public var contextAffordanceLabel: String
    public var modelLabel: String?
    public var effortLabel: String
    public var submitAccessibilityLabel: String
    public var stopAccessibilityLabel: String
    public var isSubmitVisible: Bool
    public var isStopVisible: Bool
    public var canSubmit: Bool
    public var canStop: Bool
    public var isComposerEditingDisabled: Bool

    public init(
        placeholder: String,
        contextAffordanceLabel: String,
        modelLabel: String?,
        effortLabel: String,
        submitAccessibilityLabel: String,
        stopAccessibilityLabel: String,
        isSubmitVisible: Bool,
        isStopVisible: Bool,
        canSubmit: Bool,
        canStop: Bool,
        isComposerEditingDisabled: Bool,
    ) {
        self.placeholder = placeholder
        self.contextAffordanceLabel = contextAffordanceLabel
        self.modelLabel = modelLabel
        self.effortLabel = effortLabel
        self.submitAccessibilityLabel = submitAccessibilityLabel
        self.stopAccessibilityLabel = stopAccessibilityLabel
        self.isSubmitVisible = isSubmitVisible
        self.isStopVisible = isStopVisible
        self.canSubmit = canSubmit
        self.canStop = canStop
        self.isComposerEditingDisabled = isComposerEditingDisabled
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
    public var requestID: AiChatRequestID
    public var content: String?
    public var title: String
    public var thinkingLabel: String?
    public var activityStatusLabel: String?
    public var failure: AiChatExecutionFailure?
    public var acceptedChunkRevision: Int

    public init(
        requestID: AiChatRequestID,
        content: String?,
        title: String,
        thinkingLabel: String?,
        acceptedChunkRevision: Int,
        failure: AiChatExecutionFailure? = nil,
        activityStatusLabel: String? = nil,
    ) {
        self.requestID = requestID
        self.content = content
        self.title = title
        self.thinkingLabel = Self.nonEmptyTrimmed(thinkingLabel)
        self.activityStatusLabel = Self.nonEmptyTrimmed(activityStatusLabel)
        self.failure = failure
        self.acceptedChunkRevision = acceptedChunkRevision
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 }
    }
}

enum AiChatAssistantHeaderPresentation: Equatable {
    case full, completedHistorical
    var showsVisualHeader: Bool {
        self == .full
    }

    var showsProgressIndicator: Bool {
        false
    }

    var accessibilityRoleLabel: String? {
        self == .completedHistorical ? "Assistant response" : nil
    }
}

enum AiChatAssistantResponsePresentationState: Equatable {
    case waiting
    case activeProcessingBody
    case partialFailureBody
    case terminalContentlessFailure
    case historical
}

struct AiChatAssistantBodyPresentation: Equatable {
    static let chunkFadeDuration = 0.15
    let state: AiChatAssistantResponsePresentationState
    let content: String?
    let metadataPanelLabel: String
    let showsInlineHeader: Bool
    let showsWaiting: Bool
    let isMetadataPanelEligible: Bool

    var accessibilityMetadataLabel: String? {
        isMetadataPanelEligible ? metadataPanelLabel : nil
    }

    init(
        content: String?,
        isProcessing: Bool,
        failure: AiChatExecutionFailure?,
        title: String = "Assistant",
        thinkingLabel: String? = nil,
        headerPresentation: AiChatAssistantHeaderPresentation = .full,
        requestID: AiChatRequestID? = nil,
        foregroundRequestID: AiChatRequestID? = nil,
    ) {
        let normalizedContent = Self.nonEmptyContent(content)
        self.content = normalizedContent
        metadataPanelLabel = Self.metadataLabel(title: title, thinkingLabel: thinkingLabel)
        showsInlineHeader = headerPresentation == .full && normalizedContent == nil && failure == nil
        showsWaiting = isProcessing && failure == nil && normalizedContent == nil
        isMetadataPanelEligible = headerPresentation == .full
            && normalizedContent != nil
            && isProcessing
            && failure == nil
            && requestID != nil
            && requestID == foregroundRequestID
        state = Self.resolveState(
            hasContent: normalizedContent != nil,
            isProcessing: isProcessing,
            failure: failure,
            headerPresentation: headerPresentation,
        )
    }

    static func presentsMetadataPanel(_ isEligible: Bool, _ isHovered: Bool, _ isFocused: Bool) -> Bool {
        isEligible && (isHovered || isFocused)
    }

    static func waitingText(step: Int, reduceMotion: Bool) -> String {
        guard !reduceMotion else { return "..." }
        let normalizedStep = ((step % 3) + 3) % 3
        return String(repeating: ".", count: normalizedStep + 1)
    }

    private static func nonEmptyContent(_ content: String?) -> String? {
        let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : content }
    }

    private static func metadataLabel(title: String, thinkingLabel: String?) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelTitle = normalizedTitle.isEmpty ? "Assistant" : normalizedTitle
        let trimmedThinking = thinkingLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedThinking, !trimmedThinking.isEmpty else { return modelTitle }
        return "\(modelTitle) · \(trimmedThinking)"
    }

    private static func resolveState(
        hasContent: Bool,
        isProcessing: Bool,
        failure: AiChatExecutionFailure?,
        headerPresentation: AiChatAssistantHeaderPresentation,
    ) -> AiChatAssistantResponsePresentationState {
        if headerPresentation == .completedHistorical { return .historical }
        if failure != nil { return hasContent ? .partialFailureBody : .terminalContentlessFailure }
        if isProcessing { return hasContent ? .activeProcessingBody : .waiting }
        return .historical
    }
}

extension AiChatExecutionActivityKind {
    var aiChatStatusLabel: String {
        switch self {
        case .thinking:
            "Thinking…"
        case .searching:
            "Searching…"
        case .toolExecution:
            "Running a tool…"
        case .retrying:
            "Retrying…"
        case .answerGeneration:
            "Generating answer…"
        }
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
        self.handle = handle
        self.label = label
        self.providerBadge = providerBadge
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.isDefault = isDefault
        self.isRecommended = isRecommended
    }
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

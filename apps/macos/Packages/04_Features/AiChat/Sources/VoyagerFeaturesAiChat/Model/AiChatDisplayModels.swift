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
        canStop: Bool
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
        chatInput: AiChatInputDisplayModel
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

    public var title: String { label.title }

    public init(handle: AiModelHandle, label: AiChatModelLabel) {
        self.handle = handle
        self.label = label
    }
}

public struct AiChatLockedModelDisplayModel: Equatable, Sendable {
    public var handle: AiModelHandle
    public var label: AiChatModelLabel

    public var title: String { label.title }

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
    public var id: AiModelHandle { handle }

    public var handle: AiModelHandle
    public var label: AiChatModelLabel
    public var providerBadge: String?
    public var isSelected: Bool
    public var isLocked: Bool
    public var isDefault: Bool
    public var isRecommended: Bool

    public var title: String { label.title }

    public init(
        handle: AiModelHandle,
        label: AiChatModelLabel,
        providerBadge: String?,
        isSelected: Bool,
        isLocked: Bool,
        isDefault: Bool,
        isRecommended: Bool
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
    public var id: AiProvider { provider }

    public var provider: AiProvider
    public var title: String
    public var rows: [AiChatModelCatalogRowDisplayModel]

    public init(
        provider: AiProvider,
        title: String,
        rows: [AiChatModelCatalogRowDisplayModel]
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
        lockedModel: AiChatLockedModelDisplayModel?
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
        lockedModel: AiChatLockedModelDisplayModel?
    ) {
        self.init(
            fieldLabel: fieldLabel,
            rows: rows,
            sections: [],
            selectedModel: selectedModel,
            lockedModel: lockedModel
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
        selectedModel: AiChatSelectedModelDisplayModel?
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
        isEmpty: !hasContent && (trimmedSummary?.isEmpty ?? true)
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
        fixLabel: "Open Settings"
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
        fixLabel: "Retry"
    )
}

func aiChatSessionStatusErrorMetadata(for _: AiChatState) -> AiChatConnectionMetadata? {
    nil
}

func aiChatRequestContextDisplayModel(
    currentContext: AiChatCurrentContextSnapshot,
    addedAttachments: [AiChatAttachmentDraft],
    lockedRequestContext: AiChatLockedRequestContextSnapshot?
) -> AiChatRequestContextDisplayModel {
    if let lockedRequestContext {
        return AiChatRequestContextDisplayModel(
            source: .locked,
            currentContext: aiChatCurrentContextChipDisplayModel(for: lockedRequestContext.currentContext),
            addedAttachments: lockedRequestContext.addedAttachments.map(aiChatAddedAttachmentChipDisplayModel(for:))
        )
    }

    return AiChatRequestContextDisplayModel(
        source: .draft,
        currentContext: aiChatCurrentContextChipDisplayModel(for: currentContext),
        addedAttachments: addedAttachments.map(aiChatAddedAttachmentChipDisplayModel(for:))
    )
}

private func aiChatCurrentContextChipDisplayModel(
    for snapshot: AiChatCurrentContextSnapshot
) -> AiChatCurrentContextChipDisplayModel? {
    let summary = aiChatContextSummaryDisplayModel(for: snapshot)
    guard !summary.isEmpty else { return nil }

    let title: String = if snapshot.items.count == 1 {
        snapshot.items[0].title ?? summary.title
    } else if snapshot.items.count > 1 {
        "\(snapshot.items.count) Selected"
    } else {
        summary.title
    }
    let iconSystemName = aiChatCurrentContextIconSystemName(for: snapshot)
    let iconAssetName = aiChatCurrentContextIconAssetName(for: snapshot)
    let iconFilePath = aiChatCurrentContextIconFilePath(for: snapshot)

    return AiChatCurrentContextChipDisplayModel(
        title: title,
        detail: summary.detail,
        iconSystemName: iconSystemName,
        iconAssetName: iconAssetName,
        iconFilePath: iconFilePath
    )
}

private func aiChatAddedAttachmentChipDisplayModel(
    for attachment: AiChatAttachmentDraft
) -> AiChatAddedAttachmentChipDisplayModel {
    AiChatAddedAttachmentChipDisplayModel(
        attachmentID: attachment.id,
        title: aiChatAttachmentDisplayTitle(
            id: attachment.id,
            displayTitle: attachment.displayTitle,
            sourceLocation: attachment.sourceLocation
        ),
        statusLabel: aiChatAttachmentStatusLabel(for: attachment.currentStatus),
        isRemovable: true,
        iconSystemName: aiChatAttachmentIconSystemName(for: attachment.source),
        iconAssetName: aiChatAttachmentIconAssetName(for: attachment.source),
        iconFilePath: aiChatAttachmentIconFilePath(for: attachment)
    )
}

private func aiChatAddedAttachmentChipDisplayModel(
    for attachment: AiChatAttachmentSnapshot
) -> AiChatAddedAttachmentChipDisplayModel {
    AiChatAddedAttachmentChipDisplayModel(
        attachmentID: attachment.id,
        title: aiChatAttachmentDisplayTitle(
            id: attachment.id,
            displayTitle: attachment.displayTitle,
            sourceLocation: attachment.sourceLocation
        ),
        statusLabel: aiChatAttachmentStatusLabel(for: attachment.resolutionResult),
        isRemovable: false,
        iconSystemName: aiChatAttachmentIconSystemName(for: attachment.source),
        iconAssetName: aiChatAttachmentIconAssetName(for: attachment.source),
        iconFilePath: aiChatAttachmentIconFilePath(
            source: attachment.source,
            sourceLocation: attachment.sourceLocation
        )
    )
}

private func aiChatCurrentContextIconSystemName(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        return aiChatContextIconSystemName(for: snapshot.items[0].kind)
    }
    if snapshot.items.count > 1 {
        return "checklist"
    }
    guard let route = snapshot.references.first?.metadata["route"] else { return nil }
    switch route {
    case "folder", "computer":
        return "folder"
    case "collection":
        return nil
    default:
        return nil
    }
}

private func aiChatCurrentContextIconFilePath(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        let item = snapshot.items[0]
        guard item.kind == .folder else { return nil }
        return aiChatNormalizedDisplayValue(item.metadata["path"])
    }

    guard snapshot.items.isEmpty,
          let reference = snapshot.references.first,
          reference.metadata["route"] == "folder"
    else { return nil }
    return aiChatNormalizedDisplayValue(reference.metadata["path"])
}

private func aiChatCurrentContextIconAssetName(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        return aiChatContextIconAssetName(for: snapshot.items[0])
    }
    guard snapshot.items.isEmpty,
          snapshot.references.first?.metadata["route"] == "collection"
    else { return nil }
    return aiChatCollectionIconAssetName
}

private func aiChatContextIconAssetName(for item: AiChatContextItem) -> String? {
    guard item.kind == .file,
          let path = item.metadata["path"],
          URL(fileURLWithPath: path).pathExtension.lowercased() == "voycoll"
    else { return nil }
    return aiChatCollectionIconAssetName
}

private func aiChatContextIconSystemName(for kind: AiChatContextItemKind) -> String? {
    switch kind {
    case .file:
        return "doc"
    case .folder:
        return nil
    case .attachment:
        return "paperclip"
    case .reference:
        return "doc.text"
    case .selection:
        return "checklist"
    case .note, .prompt:
        return "text.alignleft"
    case .other:
        return nil
    }
}

private func aiChatAttachmentIconSystemName(for source: AiChatAttachmentSource) -> String? {
    switch source {
    case .folder:
        return nil
    case .collectionDocument, .collectionFile:
        return nil
    case .file:
        return "doc"
    case .inlineAttachment:
        return "paperclip"
    case .otherReference:
        return nil
    }
}

private func aiChatAttachmentIconFilePath(for attachment: AiChatAttachmentDraft) -> String? {
    aiChatAttachmentIconFilePath(source: attachment.source, sourceLocation: attachment.sourceLocation)
}

private func aiChatAttachmentIconFilePath(
    source: AiChatAttachmentSource,
    sourceLocation: AiChatAttachmentSourceLocation
) -> String? {
    guard source == .folder else { return nil }
    return aiChatNormalizedDisplayValue(sourceLocation.filePath)
}

private func aiChatAttachmentIconAssetName(for source: AiChatAttachmentSource) -> String? {
    switch source {
    case .collectionDocument, .collectionFile:
        return aiChatCollectionIconAssetName
    case .file, .folder, .inlineAttachment, .otherReference:
        return nil
    }
}

private let aiChatCollectionIconAssetName = "voycollFileIcon"

private func aiChatAttachmentDisplayTitle(
    id: AiChatAttachmentID,
    displayTitle: String?,
    sourceLocation: AiChatAttachmentSourceLocation
) -> String {
    if let displayTitle = aiChatNormalizedDisplayValue(displayTitle) {
        return displayTitle
    }
    if let filePath = aiChatNormalizedDisplayValue(sourceLocation.filePath) {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    if let fileURL = sourceLocation.fileURL?.lastPathComponent,
       let normalized = aiChatNormalizedDisplayValue(fileURL)
    {
        return normalized
    }
    return id.rawValue
}

private func aiChatAttachmentStatusLabel(for status: AiChatAttachmentDraftStatus) -> String {
    switch status {
    case .pending:
        "resolving"
    case let .resolved(result):
        aiChatAttachmentStatusLabel(for: result)
    }
}

private func aiChatAttachmentStatusLabel(for result: AiChatAttachmentResolutionResult) -> String {
    switch result {
    case .resolvedText:
        "normal"
    case .resolvedReference:
        "참조만 포함 · 내용 미확장"
    case let .resolvedPartial(_, truncated, _):
        truncated ? "truncated" : "partial"
    case let .failure(reason, _):
        "failed · \(reason.rawValue)"
    }
}

private func aiChatNormalizedDisplayValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

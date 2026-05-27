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
            currentContext: aiChatCurrentContextChipDisplayModel(
                for: lockedRequestContext.currentContext,
                matchingParts: lockedRequestContext.parts.filter { $0.source == .currentContext }
            ),
            addedAttachments: lockedRequestContext.addedAttachments.map { attachment in
                aiChatAddedAttachmentChipDisplayModel(
                    for: attachment,
                    matchingPart: aiChatLockedAttachmentPart(
                        for: attachment,
                        in: lockedRequestContext.parts
                    )
                )
            }
        )
    }

    return AiChatRequestContextDisplayModel(
        source: .draft,
        currentContext: aiChatCurrentContextChipDisplayModel(for: currentContext),
        addedAttachments: addedAttachments.map(aiChatAddedAttachmentChipDisplayModel(for:))
    )
}

private func aiChatCurrentContextChipDisplayModel(
    for snapshot: AiChatCurrentContextSnapshot,
    matchingParts: [AiChatLockedContextPartSnapshot] = []
) -> AiChatCurrentContextChipDisplayModel? {
    let summary = aiChatContextSummaryDisplayModel(for: snapshot)
    guard !summary.isEmpty else { return nil }

    let title: String = if snapshot.items.count == 1 {
        aiChatCurrentContextDisplayTitle(
            snapshot.items[0].title ?? summary.title,
            snapshot: snapshot
        )
    } else if snapshot.items.count > 1 {
        "\(snapshot.items.count) Selected"
    } else {
        aiChatCurrentContextDisplayTitle(summary.title, snapshot: snapshot)
    }
    let iconSystemName = aiChatCurrentContextIconSystemName(for: snapshot)
        ?? aiChatCurrentContextIconSystemName(from: matchingParts)
    let iconAssetName = aiChatCurrentContextIconAssetName(for: snapshot)
    let iconFilePath = aiChatCurrentContextIconFilePath(for: snapshot)
        ?? aiChatCurrentContextIconFilePath(from: matchingParts)
    let supportsFolderStructureMode = aiChatSupportsFolderStructureMode(for: snapshot)
        || aiChatSupportsFolderStructureMode(from: matchingParts)
    let folderStructureMode = supportsFolderStructureMode
        ? (aiChatFolderStructureMode(for: snapshot) ?? aiChatFolderStructureMode(from: matchingParts))
        : nil

    return AiChatCurrentContextChipDisplayModel(
        title: title,
        detail: summary.detail,
        iconSystemName: iconSystemName,
        iconAssetName: iconAssetName,
        iconFilePath: iconFilePath,
        folderStructureMode: folderStructureMode,
        supportsFolderStructureMode: supportsFolderStructureMode
    )
}


private func aiChatSupportsFolderStructureMode(for snapshot: AiChatCurrentContextSnapshot) -> Bool {
    snapshot.references.contains(where: aiChatSupportsFolderStructureMode)
        || snapshot.items.contains(where: { item in
            aiChatSupportsFolderStructureMode(item)
                || item.references.contains(where: aiChatSupportsFolderStructureMode)
        })
        || snapshot.attachments.contains(where: aiChatSupportsFolderStructureMode)
}

private func aiChatSupportsFolderStructureMode(from parts: [AiChatLockedContextPartSnapshot]) -> Bool {
    parts.contains { part in
        part.fileKind == .folder
            || aiChatMetadataDescribesFolder(aiChatContextPartMetadata(part.resolution))
            || part.canonicalPath.map(aiChatPathIsDirectory) == true
    }
}

private func aiChatSupportsFolderStructureMode(_ reference: AiChatContextReference) -> Bool {
    reference.kind == .folder
        || aiChatMetadataDescribesFolder(reference.metadata)
        || aiChatPathIsDirectory(reference.metadata["path"])
        || aiChatPathIsDirectory(reference.metadata["filePath"])
        || aiChatPathIsDirectory(reference.subtitle)
        || aiChatPathIsDirectory(reference.identifier)
}

private func aiChatSupportsFolderStructureMode(_ item: AiChatContextItem) -> Bool {
    item.kind == .folder
        || aiChatMetadataDescribesFolder(item.metadata)
        || aiChatPathIsDirectory(item.metadata["path"])
        || aiChatPathIsDirectory(item.metadata["filePath"])
        || aiChatPathIsDirectory(item.subtitle)
        || aiChatPathIsDirectory(item.identifier)
}

private func aiChatSupportsFolderStructureMode(_ attachment: AiChatContextAttachment) -> Bool {
    attachment.kind == .folder
        || aiChatMetadataDescribesFolder(attachment.metadata)
        || aiChatPathIsDirectory(attachment.metadata["path"])
        || aiChatPathIsDirectory(attachment.metadata["filePath"])
        || aiChatPathIsDirectory(attachment.subtitle)
        || aiChatPathIsDirectory(attachment.identifier)
}

private func aiChatMetadataDescribesFolder(_ metadata: [String: String]) -> Bool {
    metadata["route"] == "folder" || metadata["kind"] == "folder" || metadata["fileKind"] == "folder"
}

private func aiChatPathIsDirectory(_ path: String?) -> Bool {
    guard let path, path.hasPrefix("/") else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
}

private func aiChatAddedAttachmentChipDisplayModel(
    for attachment: AiChatAttachmentDraft
) -> AiChatAddedAttachmentChipDisplayModel {
    let status = aiChatAttachmentChipStatus(for: attachment.currentStatus)
    return AiChatAddedAttachmentChipDisplayModel(
        attachmentID: attachment.id,
        title: aiChatAttachmentDisplayTitle(
            id: attachment.id,
            source: attachment.source,
            displayTitle: attachment.displayTitle,
            sourceLocation: attachment.sourceLocation
        ),
        statusLabel: status.label,
        statusDetail: aiChatAttachmentChipDetail(for: attachment.currentStatus),
        isRemovable: true,
        source: attachment.source,
        iconSystemName: aiChatAttachmentIconSystemName(for: attachment.source),
        iconAssetName: aiChatAttachmentIconAssetName(for: attachment.source),
        iconFilePath: aiChatAttachmentIconFilePath(for: attachment),
        folderStructureMode: aiChatFolderStructureMode(from: attachment.metadata)
    )
}


private func aiChatAddedAttachmentChipDisplayModel(
    for attachment: AiChatAttachmentSnapshot,
    matchingPart: AiChatLockedContextPartSnapshot? = nil
) -> AiChatAddedAttachmentChipDisplayModel {
    let statusLabel = matchingPart.map { aiChatContextPartStatusLabel(for: $0.resolution) }
        ?? aiChatAttachmentChipStatus(for: attachment.resolutionResult).label
    let statusDetail = matchingPart.map { aiChatContextPartStatusDetail(for: $0.resolution) }
        ?? aiChatAttachmentChipDetail(for: attachment.resolutionResult)
    return AiChatAddedAttachmentChipDisplayModel(
        attachmentID: attachment.id,
        title: aiChatAttachmentDisplayTitle(
            id: attachment.id,
            source: attachment.source,
            displayTitle: attachment.displayTitle,
            sourceLocation: attachment.sourceLocation
        ),
        statusLabel: statusLabel,
        statusDetail: statusDetail,
        isRemovable: false,
        source: attachment.source,
        iconSystemName: aiChatAttachmentIconSystemName(for: attachment.source),
        iconAssetName: aiChatAttachmentIconAssetName(for: attachment.source),
        iconFilePath: aiChatAttachmentIconFilePath(
            source: attachment.source,
            sourceLocation: attachment.sourceLocation
        ),
        folderStructureMode: aiChatFolderStructureMode(
            from: matchingPart.map { aiChatContextPartMetadata($0.resolution) } ?? attachment.metadata
        )
    )
}

private func aiChatFolderStructureMode(from metadata: [String: String]) -> AiChatFolderStructureMode? {
    guard let rawValue = metadata["folderStructureMode"] else { return nil }
    return AiChatFolderStructureMode(rawValue: rawValue)
}


private func aiChatFolderStructureMode(from parts: [AiChatLockedContextPartSnapshot]) -> AiChatFolderStructureMode? {
    for part in parts {
        if let mode = aiChatFolderStructureMode(from: aiChatContextPartMetadata(part.resolution)) {
            return mode
        }
    }
    return nil
}

private func aiChatFolderStructureMode(for snapshot: AiChatCurrentContextSnapshot) -> AiChatFolderStructureMode? {
    for reference in snapshot.references {
        if let mode = aiChatFolderStructureMode(from: reference.metadata) {
            return mode
        }
    }
    for item in snapshot.items {
        if let mode = aiChatFolderStructureMode(from: item.metadata) {
            return mode
        }
        for reference in item.references {
            if let mode = aiChatFolderStructureMode(from: reference.metadata) {
                return mode
            }
        }
    }
    for attachment in snapshot.attachments {
        if let mode = aiChatFolderStructureMode(from: attachment.metadata) {
            return mode
        }
    }
    return nil
}

private func aiChatAttachmentChipStatus(for status: AiChatAttachmentDraftStatus) -> AiChatRequestContextChipStatus {
    switch status {
    case .pending:
        .pending
    case let .resolved(result):
        aiChatContextPartChipStatus(for: result.contextPartResolution)
    }
}

private func aiChatAttachmentChipStatus(for result: AiChatAttachmentResolutionResult) -> AiChatRequestContextChipStatus {
    aiChatContextPartChipStatus(for: result.contextPartResolution)
}

private func aiChatAttachmentChipDetail(for result: AiChatAttachmentResolutionResult) -> String {
    aiChatContextPartChipDetail(for: result.contextPartResolution)
}

private func aiChatAttachmentChipDetail(for status: AiChatAttachmentDraftStatus) -> String {
    switch status {
    case .pending:
        ""
    case let .resolved(result):
        aiChatContextPartChipDetail(for: result.contextPartResolution)
    }
}

private func aiChatContextPartChipStatus(for resolution: AiChatContextPartResolution) -> AiChatRequestContextChipStatus {
    switch resolution {
    case .inlineText:
        .included
    case let .partialText(_, truncated, _):
        truncated ? .partial : .included
    case let .referenceOnly(metadata):
        aiChatCollectionItemPaths(from: metadata).isEmpty ? .referenceOnly : .collectionPaths
    case .collectionPathList:
        .collectionPaths
    case let .providerNativeFile(kind, _, _):
        kind == .codexPathScope ? .codexPath : .uploadedNative
    case let .failure(reason, _):
        reason == .unsupportedType ? .unsupported : .failed
    }
}

private func aiChatContextPartChipDetail(for resolution: AiChatContextPartResolution) -> String {
    switch resolution {
    case .inlineText:
        "Included as text"
    case let .partialText(_, truncated, _):
        truncated ? "Included first 64 KiB as text" : "Included as text"
    case let .referenceOnly(metadata):
        aiChatCollectionItemPaths(from: metadata).isEmpty
            ? "Reference only; contents not included"
            : "Collection paths only; contents not included"
    case .collectionPathList:
        "Collection paths only; contents not included"
    case let .providerNativeFile(kind, mimeType, _):
        kind == .codexPathScope
            ? "Codex path reference; not uploaded"
            : "Uploaded natively as \(mimeType)"
    case let .failure(reason, _):
        reason == .unsupportedType ? "Not sent: unsupported type" : "Not sent: \(reason.rawValue)"
    }
}

func aiChatContextPartStatusLabel(for resolution: AiChatContextPartResolution) -> String {
    aiChatContextPartChipStatus(for: resolution).label
}

func aiChatContextPartStatusDetail(for resolution: AiChatContextPartResolution) -> String {
    aiChatContextPartChipDetail(for: resolution)
}

private func aiChatLockedAttachmentPart(
    for attachment: AiChatAttachmentSnapshot,
    in parts: [AiChatLockedContextPartSnapshot]
) -> AiChatLockedContextPartSnapshot? {
    parts.first { part in
        guard part.source == .attachment else { return false }
        return aiChatContextPartMetadata(part.resolution)["attachmentID"] == attachment.id.rawValue
    }
}

private func aiChatContextPartMetadata(_ resolution: AiChatContextPartResolution) -> [String: String] {
    switch resolution {
    case let .inlineText(_, metadata),
         let .partialText(_, _, metadata),
         let .referenceOnly(metadata),
         let .collectionPathList(_, metadata),
         let .providerNativeFile(_, _, metadata),
         let .failure(_, metadata):
        metadata
    }
}

private func aiChatCollectionItemPaths(from metadata: [String: String]) -> [String] {
    guard let rawPaths = metadata["collectionItemPaths"] else { return [] }
    return rawPaths
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func aiChatRequestContextTooltipText(
    sourceLabel: String,
    destinationLabel: String,
    statusLabel: String,
    statusDetail: String
) -> String {
    [
        "Source: \(sourceLabel)",
        "Destination: \(destinationLabel)",
        statusLabel.isEmpty ? "" : "Status: \(statusLabel)",
        statusDetail,
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " · ")
}

func aiChatCurrentContextStatusLabel(
    for snapshot: AiChatCurrentContextSnapshot,
    destinationProvider: AiProvider?
) -> String {
    if aiChatCurrentContextIsCollection(snapshot) {
        return "Collection paths"
    }

    if aiChatCurrentContextIsReferenceOnly(snapshot) {
        return "Reference only"
    }

    if aiChatCurrentContextContainsFileLikeContent(snapshot) {
        return destinationProvider == .chatgptCodex ? "Codex path" : "Included"
    }

    return snapshot.references.isEmpty && snapshot.items.isEmpty && snapshot.attachments.isEmpty
        ? "Reference only"
        : "Included"
}

func aiChatCurrentContextStatusDetail(
    for snapshot: AiChatCurrentContextSnapshot,
    destinationProvider: AiProvider?
) -> String {
    switch aiChatCurrentContextStatusLabel(for: snapshot, destinationProvider: destinationProvider) {
    case "Collection paths":
        "Collection paths only; contents not included"
    case "Reference only":
        "Reference only; contents not included"
    case "Codex path":
        "Codex path reference; not uploaded"
    case "Included":
        destinationProvider == .chatgptCodex
            ? "Codex path reference; not uploaded"
            : "May be included as text or provider-native file when supported"
    default:
        "Contents not included"
    }
}

private func aiChatCurrentContextIsReferenceOnly(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
    snapshot.items.contains { $0.kind == .folder }
        || snapshot.references.contains { $0.metadata["route"] == "folder" }
}

private func aiChatCurrentContextContainsFileLikeContent(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
    snapshot.items.contains { $0.kind == .file || $0.kind == .attachment }
        || snapshot.references.contains { reference in
            reference.metadata["path"] != nil || reference.metadata["filePath"] != nil
        }
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


private func aiChatCurrentContextIconSystemName(from parts: [AiChatLockedContextPartSnapshot]) -> String? {
    parts.contains { $0.fileKind == .folder } ? "folder" : nil
}

private func aiChatCurrentContextIconFilePath(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        let item = snapshot.items[0]
        guard item.kind == .folder else { return nil }
        return aiChatAbsoluteIconFilePath(item.metadata["path"])
    }

    guard snapshot.items.isEmpty,
          let reference = snapshot.references.first,
          reference.metadata["route"] == "folder"
    else { return nil }
    return aiChatAbsoluteIconFilePath(reference.metadata["path"])
}

private func aiChatAbsoluteIconFilePath(_ value: String?) -> String? {
    guard let path = aiChatNormalizedDisplayValue(value), path.hasPrefix("/") else { return nil }
    return path
}

private func aiChatCurrentContextIconFilePath(from parts: [AiChatLockedContextPartSnapshot]) -> String? {
    for part in parts where part.fileKind == .folder {
        if let canonicalPath = aiChatNormalizedDisplayValue(part.canonicalPath) {
            return canonicalPath
        }
    }
    return nil
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

private func aiChatCurrentContextDisplayTitle(
    _ title: String,
    snapshot: AiChatCurrentContextSnapshot
) -> String {
    guard aiChatCurrentContextIsCollection(snapshot) else { return title }
    return aiChatDisplayTitleByRemovingCollectionExtension(title)
}

private func aiChatCurrentContextIsCollection(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
    if snapshot.items.count == 1 {
        let item = snapshot.items[0]
        if let path = item.metadata["path"],
           URL(fileURLWithPath: path).pathExtension.lowercased() == "voycoll"
        {
            return true
        }
        return item.title?.lowercased().hasSuffix(".voycoll") == true
    }

    guard snapshot.items.isEmpty,
          let reference = snapshot.references.first
    else { return false }

    if reference.metadata["route"] == "collection" {
        return true
    }
    if let path = reference.metadata["path"],
       URL(fileURLWithPath: path).pathExtension.lowercased() == "voycoll"
    {
        return true
    }
    return reference.title?.lowercased().hasSuffix(".voycoll") == true
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
    switch source {
    case .folder, .collectionDocument, .collectionFile:
        return aiChatNormalizedDisplayValue(sourceLocation.filePath)
    case .file, .inlineAttachment, .otherReference:
        return nil
    }
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
    source: AiChatAttachmentSource,
    displayTitle: String?,
    sourceLocation: AiChatAttachmentSourceLocation
) -> String {
    let title = if let displayTitle = aiChatNormalizedDisplayValue(displayTitle) {
        displayTitle
    } else if let filePath = aiChatNormalizedDisplayValue(sourceLocation.filePath) {
        URL(fileURLWithPath: filePath).lastPathComponent
    } else if let fileURL = sourceLocation.fileURL?.lastPathComponent,
              let normalized = aiChatNormalizedDisplayValue(fileURL)
    {
        normalized
    } else {
        id.rawValue
    }

    return aiChatDisplayTitleByRemovingCollectionExtension(title, source: source)
}

private func aiChatDisplayTitleByRemovingCollectionExtension(
    _ title: String,
    source: AiChatAttachmentSource
) -> String {
    guard source == .collectionDocument || source == .collectionFile else { return title }
    return aiChatDisplayTitleByRemovingCollectionExtension(title)
}

private func aiChatDisplayTitleByRemovingCollectionExtension(_ title: String) -> String {
    let url = URL(fileURLWithPath: title)
    guard url.pathExtension.lowercased() == "voycoll" else { return title }
    let strippedTitle = url.deletingPathExtension().lastPathComponent
    return strippedTitle.isEmpty ? title : strippedTitle
}

private struct AiChatRequestContextChipStatus: Equatable, Sendable {
    let label: String
    let detail: String

    static let included = Self(label: "Included", detail: "Included as text")
    static let partial = Self(label: "Partial", detail: "Included first 64 KiB as text")
    static let referenceOnly = Self(label: "Reference only", detail: "Reference only; contents not included")
    static let collectionPaths = Self(label: "Collection paths", detail: "Collection paths only; contents not included")
    static let pending = Self(label: "", detail: "")
    static let uploadedNative = Self(label: "Uploaded/native", detail: "Uploaded natively as provider file")
    static let unsupported = Self(label: "Unsupported", detail: "Not sent: unsupported type")
    static let failed = Self(label: "Failed", detail: "Not sent")
    static let codexPath = Self(label: "Codex path", detail: "Codex path reference; not uploaded")
}

private func aiChatNormalizedDisplayValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

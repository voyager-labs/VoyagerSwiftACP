import Foundation
import VoyagerEntitiesAi

func aiChatRequestContextDisplayModel(
    currentContext: AiChatCurrentContextSnapshot,
    addedAttachments: [AiChatAttachmentDraft],
) -> AiChatRequestContextDisplayModel {
    AiChatRequestContextDisplayModel(
        currentContext: aiChatCurrentContextChipDisplayModel(for: currentContext),
        addedAttachments: addedAttachments.map(aiChatAddedAttachmentChipDisplayModel(for:)),
    )
}

private func aiChatCurrentContextChipDisplayModel(
    for snapshot: AiChatCurrentContextSnapshot,
) -> AiChatCurrentContextChipDisplayModel? {
    let summary = aiChatContextSummaryDisplayModel(for: snapshot)
    guard !summary.isEmpty else { return nil }

    let title: String = if snapshot.items.count == 1 {
        aiChatCurrentContextDisplayTitle(
            snapshot.items[0].title ?? summary.title,
            snapshot: snapshot,
        )
    } else if snapshot.items.count > 1 {
        "\(snapshot.items.count) Selected"
    } else {
        aiChatCurrentContextDisplayTitle(summary.title, snapshot: snapshot)
    }
    let iconSystemName = aiChatCurrentContextIconSystemName(for: snapshot)
    let iconAssetName = aiChatCurrentContextIconAssetName(for: snapshot)
    let iconFilePath = aiChatCurrentContextIconFilePath(for: snapshot)
    let supportsFolderStructureMode = aiChatSupportsFolderStructureMode(for: snapshot)
    let folderStructureMode = supportsFolderStructureMode
        ? aiChatFolderStructureMode(for: snapshot)
        : nil

    return AiChatCurrentContextChipDisplayModel(
        title: title,
        detail: summary.detail,
        iconSystemName: iconSystemName,
        iconAssetName: iconAssetName,
        iconFilePath: iconFilePath,
        folderStructureMode: folderStructureMode,
        supportsFolderStructureMode: supportsFolderStructureMode,
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

func aiChatMetadataDescribesFolder(_ metadata: [String: String]) -> Bool {
    metadata["route"] == "folder" || metadata["kind"] == "folder" || metadata["fileKind"] == "folder"
}

func aiChatPathIsDirectory(_ path: String?) -> Bool {
    guard let path, path.hasPrefix("/") else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
}

private func aiChatAddedAttachmentChipDisplayModel(
    for attachment: AiChatAttachmentDraft,
) -> AiChatAddedAttachmentChipDisplayModel {
    let status = aiChatAttachmentChipStatus(for: attachment.currentStatus)
    return AiChatAddedAttachmentChipDisplayModel(
        attachmentID: attachment.id,
        title: aiChatAttachmentDisplayTitle(
            id: attachment.id,
            source: attachment.source,
            displayTitle: attachment.displayTitle,
            sourceLocation: attachment.sourceLocation,
        ),
        statusLabel: status.label,
        statusDetail: aiChatAttachmentChipDetail(for: attachment.currentStatus),
        isRemovable: true,
        source: attachment.source,
        iconSystemName: aiChatAttachmentIconSystemName(for: attachment.source),
        iconAssetName: aiChatAttachmentIconAssetName(for: attachment.source),
        iconFilePath: aiChatAttachmentIconFilePath(for: attachment),
        folderStructureMode: aiChatFolderStructureMode(from: attachment.metadata),
    )
}

private func aiChatFolderStructureMode(from metadata: [String: String]) -> AiChatFolderStructureMode? {
    guard let rawValue = metadata["folderStructureMode"] else { return nil }
    return AiChatFolderStructureMode(rawValue: rawValue)
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

private func aiChatAttachmentChipStatus(for result: AiChatAttachmentResolutionResult)
    -> AiChatRequestContextChipStatus
{
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

private func aiChatContextPartChipStatus(for resolution: AiChatContextPartResolution)
    -> AiChatRequestContextChipStatus
{
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

func aiChatContextPartMetadata(_ resolution: AiChatContextPartResolution) -> [String: String] {
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

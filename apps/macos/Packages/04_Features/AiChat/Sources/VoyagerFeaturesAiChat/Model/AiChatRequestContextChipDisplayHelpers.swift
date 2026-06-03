import Foundation
import VoyagerEntitiesAi

let kAiChatCollectionIconAssetName = "voycollFileIcon"

func aiChatRequestContextTooltipText(
    sourceLabel: String,
    destinationLabel: String,
    statusLabel: String,
    statusDetail: String,
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
    destinationProvider: AiProvider?,
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
    destinationProvider: AiProvider?,
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

func aiChatCurrentContextIsReferenceOnly(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
    snapshot.items.contains { $0.kind == .folder }
        || snapshot.references.contains { $0.metadata["route"] == "folder" }
}

func aiChatCurrentContextContainsFileLikeContent(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
    snapshot.items.contains { $0.kind == .file || $0.kind == .attachment }
        || snapshot.references.contains { reference in
            reference.metadata["path"] != nil || reference.metadata["filePath"] != nil
        }
}

func aiChatCurrentContextIconSystemName(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        return aiChatContextIconSystemName(for: snapshot.items[0].kind)
    }
    if snapshot.items.count > 1 {
        return "checklist"
    }
    if snapshot.attachments.count == 1 {
        return aiChatContextIconSystemName(for: snapshot.attachments[0].kind)
    }
    if snapshot.attachments.count > 1 {
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

func aiChatCurrentContextIconSystemName(from parts: [AiChatLockedContextPartSnapshot]) -> String? {
    parts.contains { $0.fileKind == .folder } ? "folder" : nil
}

func aiChatCurrentContextIconFilePath(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        let item = snapshot.items[0]
        guard item.kind == .folder else { return nil }
        return aiChatAbsoluteIconFilePath(item.metadata["path"])
    }
    if snapshot.attachments.count == 1 {
        let attachment = snapshot.attachments[0]
        guard attachment.kind == .folder else { return nil }
        return aiChatAbsoluteIconFilePath(attachment.metadata["path"])
            ?? aiChatAbsoluteIconFilePath(attachment.metadata["filePath"])
            ?? aiChatAbsoluteIconFilePath(attachment.subtitle)
            ?? aiChatAbsoluteIconFilePath(attachment.identifier)
    }

    guard snapshot.items.isEmpty,
          snapshot.attachments.isEmpty,
          let reference = snapshot.references.first,
          reference.metadata["route"] == "folder"
    else { return nil }
    return aiChatAbsoluteIconFilePath(reference.metadata["path"])
}

func aiChatAbsoluteIconFilePath(_ value: String?) -> String? {
    guard let path = aiChatNormalizedDisplayValue(value), path.hasPrefix("/") else { return nil }
    return path
}

func aiChatCurrentContextIconFilePath(from parts: [AiChatLockedContextPartSnapshot]) -> String? {
    for part in parts where aiChatLockedContextPartDescribesFolder(part) {
        if let canonicalPath = aiChatNormalizedDisplayValue(part.canonicalPath) {
            return canonicalPath
        }
    }
    return nil
}

func aiChatLockedContextPartDescribesFolder(_ part: AiChatLockedContextPartSnapshot) -> Bool {
    part.fileKind == .folder
        || aiChatMetadataDescribesFolder(aiChatContextPartMetadata(part.resolution))
        || part.canonicalPath.map(aiChatPathIsDirectory) == true
}

func aiChatCurrentContextIconAssetName(for snapshot: AiChatCurrentContextSnapshot) -> String? {
    if snapshot.items.count == 1 {
        return aiChatContextIconAssetName(for: snapshot.items[0])
    }
    if snapshot.attachments.count == 1 {
        return aiChatContextIconAssetName(for: snapshot.attachments[0])
    }
    guard snapshot.items.isEmpty,
          snapshot.attachments.isEmpty,
          snapshot.references.first?.metadata["route"] == "collection"
    else { return nil }
    return kAiChatCollectionIconAssetName
}

func aiChatContextIconAssetName(for item: AiChatContextItem) -> String? {
    guard item.kind == .file,
          let path = item.metadata["path"],
          URL(fileURLWithPath: path).pathExtension.lowercased() == "voycoll"
    else { return nil }
    return kAiChatCollectionIconAssetName
}

func aiChatContextIconAssetName(for attachment: AiChatContextAttachment) -> String? {
    guard attachment.kind == .file,
          let path = attachment.metadata["path"] ?? attachment.metadata["filePath"],
          URL(fileURLWithPath: path).pathExtension.lowercased() == "voycoll"
    else { return nil }
    return kAiChatCollectionIconAssetName
}

func aiChatCurrentContextDisplayTitle(
    _ title: String,
    snapshot: AiChatCurrentContextSnapshot,
) -> String {
    guard aiChatCurrentContextIsCollection(snapshot) else { return title }
    return aiChatDisplayTitleByRemovingCollectionExtension(title)
}

func aiChatCurrentContextIsCollection(_ snapshot: AiChatCurrentContextSnapshot) -> Bool {
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

func aiChatContextIconSystemName(for kind: AiChatContextItemKind) -> String? {
    switch kind {
    case .file:
        "doc"
    case .folder:
        nil
    case .attachment:
        "paperclip"
    case .reference:
        "doc.text"
    case .selection:
        "checklist"
    case .note, .prompt:
        "text.alignleft"
    case .other:
        nil
    }
}

func aiChatAttachmentIconSystemName(for source: AiChatAttachmentSource) -> String? {
    switch source {
    case .folder:
        nil
    case .collectionDocument, .collectionFile:
        nil
    case .file:
        "doc"
    case .inlineAttachment:
        "paperclip"
    case .otherReference:
        nil
    }
}

func aiChatAttachmentIconFilePath(for attachment: AiChatAttachmentDraft) -> String? {
    aiChatAttachmentIconFilePath(source: attachment.source, sourceLocation: attachment.sourceLocation)
}

func aiChatAttachmentIconFilePath(
    source: AiChatAttachmentSource,
    sourceLocation: AiChatAttachmentSourceLocation,
) -> String? {
    switch source {
    case .folder, .collectionDocument, .collectionFile:
        aiChatNormalizedDisplayValue(sourceLocation.filePath)
    case .file, .inlineAttachment, .otherReference:
        nil
    }
}

func aiChatAttachmentIconAssetName(for source: AiChatAttachmentSource) -> String? {
    switch source {
    case .collectionDocument, .collectionFile:
        kAiChatCollectionIconAssetName
    case .file, .folder, .inlineAttachment, .otherReference:
        nil
    }
}

func aiChatAttachmentDisplayTitle(
    id: AiChatAttachmentID,
    source: AiChatAttachmentSource,
    displayTitle: String?,
    sourceLocation: AiChatAttachmentSourceLocation,
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

func aiChatDisplayTitleByRemovingCollectionExtension(
    _ title: String,
    source: AiChatAttachmentSource,
) -> String {
    guard source == .collectionDocument || source == .collectionFile else { return title }
    return aiChatDisplayTitleByRemovingCollectionExtension(title)
}

func aiChatDisplayTitleByRemovingCollectionExtension(_ title: String) -> String {
    let url = URL(fileURLWithPath: title)
    guard url.pathExtension.lowercased() == "voycoll" else { return title }
    let strippedTitle = url.deletingPathExtension().lastPathComponent
    return strippedTitle.isEmpty ? title : strippedTitle
}

struct AiChatRequestContextChipStatus: Equatable {
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

func aiChatNormalizedDisplayValue(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

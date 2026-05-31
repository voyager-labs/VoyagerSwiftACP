import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

extension AiChatAttachmentResolverClient {
    static func resolveAttachment(
        _ attachment: AiChatAttachmentDraft,
        remainingTotalBudget: inout Int,
        fileManagerClient: FileManagerClient,
    ) -> AiChatAttachmentResolutionResult {
        guard remainingTotalBudget > 0 else {
            return .failure(reason: .tooLarge, metadata: attachmentResolutionMetadata(for: attachment))
        }

        if attachment.source == .folder {
            let metadata = folderStructureMetadata(
                base: attachmentResolutionMetadata(for: attachment),
                directoryURL: attachmentResolutionURL(for: attachment),
                mode: folderStructureMode(from: attachment.metadata),
                fileManagerClient: fileManagerClient,
            )
            return .resolvedReference(metadata: metadata)
        }

        if attachment.source == .collectionDocument || attachment.source == .collectionFile {
            return resolveCollectionAttachment(attachment, remainingTotalBudget: &remainingTotalBudget)
        }

        guard let fileURL = attachmentResolutionURL(for: attachment) else {
            return .failure(reason: .brokenReference, metadata: attachmentResolutionMetadata(for: attachment))
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if resourceValues?.isDirectory == true {
            let metadata = folderStructureMetadata(
                base: attachmentResolutionMetadata(for: attachment),
                directoryURL: fileURL,
                mode: folderStructureMode(from: attachment.metadata),
                fileManagerClient: fileManagerClient,
            )
            return .resolvedReference(metadata: metadata)
        }

        guard resourceValues?.isRegularFile != false else {
            return .failure(reason: .unsupportedType, metadata: attachmentResolutionMetadata(for: attachment))
        }

        return resolveFileAttachment(
            attachment,
            fileURL: fileURL,
            relativePath: fileURL.lastPathComponent,
            remainingTotalBudget: &remainingTotalBudget,
        )
    }

    static func resolveCollectionAttachment(
        _ attachment: AiChatAttachmentDraft,
        remainingTotalBudget: inout Int,
    ) -> AiChatAttachmentResolutionResult {
        let metadata = collectionReferenceMetadata(
            base: attachmentResolutionMetadata(for: attachment),
            fileURL: attachmentResolutionURL(for: attachment),
            remainingTotalBudget: &remainingTotalBudget,
        )
        return .resolvedReference(metadata: metadata)
    }

    static func collectionReferenceMetadata(
        base: [String: String],
        fileURL: URL?,
        remainingTotalBudget: inout Int,
    ) -> [String: String] {
        var metadata = base
        guard let fileURL else {
            metadata["collectionSnapshotStatus"] = CollectionFileReferenceSnapshotStatus.missing.rawValue
            return metadata
        }

        let snapshot = CollectionFileReferenceExtractor.referenceSnapshot(at: fileURL)
        metadata["collectionSnapshotStatus"] = snapshot.status.rawValue
        if let itemCount = snapshot.itemCount {
            metadata["collectionItemCount"] = "\(itemCount)"
        }

        if !snapshot.itemPaths.isEmpty {
            let resolvedPaths = collectionItemPathsWithinBudget(
                snapshot.itemPaths,
                budget: min(collectionItemPathUTF8ByteBudget, remainingTotalBudget),
            )
            metadata["collectionItemsIncluded"] = "\(resolvedPaths.paths.count)"
            metadata["collectionItemsTruncated"] = resolvedPaths.truncated ? "true" : "false"
            metadata["collectionItemPathUTF8ByteBudget"] = "\(collectionItemPathUTF8ByteBudget)"
            metadata["collectionItemPathsUTF8Bytes"] = "\(resolvedPaths.utf8Bytes)"
            remainingTotalBudget -= resolvedPaths.utf8Bytes
            if !resolvedPaths.paths.isEmpty {
                metadata["collectionItemPaths"] = resolvedPaths.paths.joined(separator: "\n")
            }
        }
        return metadata
    }

    static let perAttachmentUTF8ByteBudget = 64 * 1024
    static let totalAttachmentTextUTF8ByteBudget = 128 * 1024
    static let collectionItemPathUTF8ByteBudget = perAttachmentUTF8ByteBudget

    static func collectionItemPathsWithinBudget(
        _ paths: [String],
        budget: Int,
    ) -> AiChatCollectionItemPathBudgetResult {
        var includedPaths: [String] = []
        var usedBytes = 0

        for path in paths {
            let separatorBytes = includedPaths.isEmpty ? 0 : 1
            let pathBytes = path.utf8.count
            guard usedBytes + separatorBytes + pathBytes <= budget else {
                return AiChatCollectionItemPathBudgetResult(paths: includedPaths, utf8Bytes: usedBytes, truncated: true)
            }
            includedPaths.append(path)
            usedBytes += separatorBytes + pathBytes
        }

        return AiChatCollectionItemPathBudgetResult(paths: includedPaths, utf8Bytes: usedBytes, truncated: false)
    }

    static func resolveFileAttachment(
        _ attachment: AiChatAttachmentDraft,
        fileURL: URL,
        relativePath: String,
        remainingTotalBudget: inout Int,
    ) -> AiChatAttachmentResolutionResult {
        var metadata = attachmentResolutionMetadata(for: attachment)
        metadata["relativePath"] = relativePath

        switch resolveFileText(fileURL: fileURL, remainingTotalBudget: &remainingTotalBudget) {
        case let .success(text, truncated):
            return truncated
                ? .resolvedPartial(text: text, truncated: true, metadata: metadata)
                : .resolvedText(text: text, metadata: metadata)
        case let .failure(reason):
            return .failure(reason: reason, metadata: metadata)
        }
    }

    enum ResolvedAttachmentText {
        case success(text: String, truncated: Bool)
        case failure(AiChatAttachmentResolutionFailure)
    }

    static func resolveFileText(
        fileURL: URL,
        remainingTotalBudget: inout Int,
    ) -> ResolvedAttachmentText {
        let allowedBytes = min(perAttachmentUTF8ByteBudget, remainingTotalBudget)
        guard allowedBytes > 0 else { return .failure(.tooLarge) }

        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? fileHandle.close()
            }

            guard let data = try fileHandle.read(upToCount: allowedBytes + 1), !data.isEmpty else {
                return .failure(.emptyContent)
            }
            let truncated = data.count > allowedBytes
            let selectedData = truncated ? data.prefix(allowedBytes) : data[...]
            guard let decoded = decodeUTF8Prefix(Data(selectedData)) else {
                return .failure(.unsupportedType)
            }
            let normalizedText = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return .failure(.emptyContent) }
            remainingTotalBudget -= decoded.byteCount
            return .success(text: normalizedText, truncated: truncated)
        } catch CocoaError.fileReadNoPermission {
            return .failure(.permissionDenied)
        } catch {
            return .failure(.readFailed)
        }
    }

    static func attachmentResolutionURL(for attachment: AiChatAttachmentDraft) -> URL? {
        if let fileURL = attachment.sourceLocation.fileURL {
            return fileURL.standardizedFileURL
        }
        if let filePath = attachment.sourceLocation.filePath, !filePath.isEmpty {
            return URL(fileURLWithPath: filePath).standardizedFileURL
        }
        return nil
    }

    static func attachmentResolutionMetadata(for attachment: AiChatAttachmentDraft) -> [String: String] {
        var metadata = attachment.metadata
        metadata["source"] = attachment.source.rawValue
        if let filePath = attachment.sourceLocation.filePath, !filePath.isEmpty {
            metadata["filePath"] = filePath
        }
        return metadata
    }
}

struct AiChatCollectionItemPathBudgetResult {
    let paths: [String]
    let utf8Bytes: Int
    let truncated: Bool
}

struct AiChatResolvedAttachmentDescriptor {
    let snapshot: AiChatAttachmentSnapshot
    let part: AiChatResolvedContextPart
}

struct AiChatResolvedCurrentContext {
    let snapshot: AiChatCurrentContextSnapshot
    let parts: [AiChatResolvedContextPart]
}

struct AiChatCurrentContextElementDescriptor<Element> {
    let snapshotElement: Element
    let part: AiChatResolvedContextPart?
}

struct AiChatResolvedFileIdentity {
    let originalURL: URL
    let canonicalURL: URL
    let displayPath: String
    let isDirectory: Bool
    let isRegularFile: Bool
    let sizeBytes: Int64?
    let mimeType: String
    let contentTypeIdentifier: String?
    let fileExtension: String?
}

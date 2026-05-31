import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

extension AiChatContextPartResolverClient {
    static func sanitizeAttachmentSnapshot(
        _ snapshot: AiChatAttachmentSnapshot,
        provider: AiProvider,
        displayPath: String?,
    ) -> AiChatAttachmentSnapshot {
        let sanitizedLocation = sanitizeSourceLocation(
            snapshot.sourceLocation,
            provider: provider,
            displayPath: displayPath,
        )
        return AiChatAttachmentSnapshot(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: sanitizeContextScalar(snapshot.subtitle, provider: provider),
            kind: snapshot.kind,
            sourceLocation: sanitizedLocation,
            metadata: sanitizeContextMetadata(snapshot.metadata, provider: provider),
            resolutionResult: sanitizeResolutionResult(snapshot.resolutionResult, provider: provider),
        )
    }

    static func sanitizeResolutionResult(
        _ resolutionResult: AiChatAttachmentResolutionResult,
        provider: AiProvider,
    ) -> AiChatAttachmentResolutionResult {
        switch resolutionResult {
        case let .resolvedText(text, metadata):
            .resolvedText(text: text, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .resolvedReference(metadata):
            .resolvedReference(metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .resolvedPartial(text, truncated, metadata):
            .resolvedPartial(
                text: text,
                truncated: truncated,
                metadata: sanitizeContextMetadata(metadata, provider: provider),
            )
        case let .failure(reason, metadata):
            .failure(reason: reason, metadata: sanitizeContextMetadata(metadata, provider: provider))
        }
    }

    static func sanitizeSourceLocation(
        _ sourceLocation: AiChatAttachmentSourceLocation,
        provider _: AiProvider,
        displayPath _: String?,
    ) -> AiChatAttachmentSourceLocation {
        sourceLocation
    }

    static func nativeUploadData(fileURL: URL, safeLimitBytes: Int64) -> Data? {
        guard safeLimitBytes > 0 else { return nil }
        let sentinelLimit = safeLimitBytes + 1
        guard sentinelLimit <= Int64(Int.max) else { return nil }

        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? fileHandle.close()
            }

            guard let data = try fileHandle.read(upToCount: Int(sentinelLimit)),
                  !data.isEmpty,
                  Int64(data.count) <= safeLimitBytes
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    static func providerRequestFamily(
        for requestFamily: AiChatContextPartResolverRequestFamily,
    ) -> AiChatProviderRequestFamily {
        switch requestFamily {
        case .openAIResponses:
            .openAIResponses
        case .anthropicMessages:
            .anthropicMessages
        case .codexCLI:
            .codexCLI
        }
    }

    static func resolutionMetadata(from resolution: AiChatContextPartResolution) -> [String: String] {
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

    static func addingAttachmentID(
        to resolution: AiChatContextPartResolution,
        attachmentID: String,
    ) -> AiChatContextPartResolution {
        func metadataWithAttachmentID(_ metadata: [String: String]) -> [String: String] {
            var metadata = metadata
            metadata["attachmentID"] = attachmentID
            return metadata
        }

        switch resolution {
        case let .inlineText(text, metadata):
            return .inlineText(text: text, metadata: metadataWithAttachmentID(metadata))
        case let .partialText(text, truncated, metadata):
            return .partialText(text: text, truncated: truncated, metadata: metadataWithAttachmentID(metadata))
        case let .referenceOnly(metadata):
            return .referenceOnly(metadata: metadataWithAttachmentID(metadata))
        case let .collectionPathList(paths, metadata):
            return .collectionPathList(paths: paths, metadata: metadataWithAttachmentID(metadata))
        case let .providerNativeFile(kind, mimeType, metadata):
            return .providerNativeFile(kind: kind, mimeType: mimeType, metadata: metadataWithAttachmentID(metadata))
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: metadataWithAttachmentID(metadata))
        }
    }

    static func sanitizeContextPartResolution(
        from resolution: AiChatContextPartResolution,
        provider: AiProvider,
    ) -> AiChatContextPartResolution {
        switch resolution {
        case let .inlineText(text, metadata):
            return .inlineText(text: text, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .partialText(text, truncated, metadata):
            return .partialText(
                text: text,
                truncated: truncated,
                metadata: sanitizeContextMetadata(metadata, provider: provider),
            )
        case let .referenceOnly(metadata):
            return .referenceOnly(metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .collectionPathList(paths, metadata):
            let sanitizedPaths = provider == .chatgptCodex
                ? paths
                : paths.compactMap { path in
                    sanitizeContextScalar(path, provider: provider)
                }
            return .collectionPathList(
                paths: sanitizedPaths,
                metadata: sanitizeContextMetadata(metadata, provider: provider),
            )
        case let .providerNativeFile(kind, mimeType, metadata):
            return .providerNativeFile(
                kind: kind,
                mimeType: mimeType,
                metadata: sanitizeContextMetadata(metadata, provider: provider),
            )
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: sanitizeContextMetadata(metadata, provider: provider))
        }
    }

    static func mergedResolutionMetadata(
        _ metadata: [String: String],
        displayPath: String?,
        mimeType: String?,
        provider: AiProvider,
    ) -> [String: String] {
        var merged = sanitizeContextMetadata(metadata, provider: provider)
        if let displayPath {
            merged["displayPath"] = displayPath
        }
        if let mimeType {
            merged["mimeType"] = mimeType
        }
        return merged
    }

    static func sanitizeContextMetadata(_ metadata: [String: String], provider: AiProvider) -> [String: String] {
        guard provider != .chatgptCodex else { return metadata }
        var sanitized = metadata
        for key in ["path", "filePath", "relativePath"] {
            if let value = sanitized[key] {
                sanitized[key] = displayPath(for: value, provider: provider)
            }
        }
        if let collectionItemPaths = sanitized["collectionItemPaths"] {
            let sanitizedPaths = collectionItemPaths
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .compactMap { sanitizeContextScalar($0, provider: provider) }
            let joinedPaths = sanitizedPaths.joined(separator: "\n")
            sanitized["collectionItemPaths"] = joinedPaths
            sanitized["collectionItemPathsUTF8Bytes"] = "\(joinedPaths.utf8.count)"
        }
        return sanitized
    }

    static func sanitizeContextScalar(_ value: String?, provider: AiProvider) -> String? {
        guard let value else { return nil }
        return displayPath(for: value, provider: provider)
    }

    static func displayPath(for value: String?, provider: AiProvider) -> String? {
        guard let value = normalizedNonEmpty(value) else { return nil }
        guard provider != .chatgptCodex else { return value }
        guard value.hasPrefix("/") else { return value }
        let filename = URL(fileURLWithPath: value).lastPathComponent
        return filename.isEmpty ? value : filename
    }

    static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

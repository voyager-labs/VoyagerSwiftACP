import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

struct ProviderIdentity {
    let provider: AiProvider
    let rawModelID: String
}

extension AiChatContextPartResolverClient {
    static func makeAttachmentDescriptor(
        draft: AiChatAttachmentDraft,
        snapshot: AiChatAttachmentSnapshot,
        config _: AiChatContextResolveConfig,
    ) -> AiChatResolvedAttachmentDescriptor {
        let fileIdentity = AiChatAttachmentResolverClient.attachmentResolutionURL(for: draft)
            .flatMap(resolveFileIdentity)
        let sanitizedSnapshot = sanitizeAttachmentSnapshot(
            snapshot,
            provider: config.provider,
            displayPath: fileIdentity?.displayPath,
        )
        let part = AiChatResolvedContextPart(
            source: .attachment,
            resolution: attachmentPartResolution(
                draft: draft,
                snapshot: sanitizedSnapshot,
                fileIdentity: fileIdentity,
                providerIdentity: ProviderIdentity(provider: config.provider, rawModelID: config.rawModelID),
                requestFamily: config.requestFamily,
            ),
            fileKind: draft.kind,
            canonicalPath: fileIdentity?.canonicalURL.path(percentEncoded: false),
            displayPath: fileIdentity?.displayPath,
            displayTitle: sanitizedSnapshot.displayTitle,
            byteCount: fileIdentity?.sizeBytes,
            mimeType: fileIdentity?.mimeType,
        )
        return AiChatResolvedAttachmentDescriptor(snapshot: sanitizedSnapshot, part: part)
    }

    static func attachmentPartResolution(
        draft: AiChatAttachmentDraft,
        snapshot: AiChatAttachmentSnapshot,
        fileIdentity: AiChatResolvedFileIdentity?,
        providerIdentity _: ProviderIdentity,
        requestFamily: AiChatContextPartResolverRequestFamily,
    ) -> AiChatContextPartResolution {
        let fallbackResolution = addingAttachmentID(
            to: Self.sanitizeContextPartResolution(
                from: snapshot.resolutionResult.contextPartResolution,
                provider: providerIdentity.provider,
            ),
            attachmentID: draft.id.rawValue,
        )
        guard draft.source == .file,
              let fileIdentity,
              fileIdentity.isRegularFile,
              !fileIdentity.isDirectory
        else {
            return fallbackResolution
        }

        if providerIdentity.provider == .chatgptCodex {
            return codexAttachmentPartResolution(
                snapshot: snapshot,
                fileIdentity: fileIdentity,
                provider: providerIdentity.provider,
                attachmentID: draft.id.rawValue,
            )
        }

        return nativeAttachmentPartResolution(AiChatAttachmentNativeResolutionInput(
            draft: draft,
            snapshot: snapshot,
            fallbackResolution: fallbackResolution,
            fileIdentity: fileIdentity,
            provider: providerIdentity.provider,
            rawModelID: providerIdentity.rawModelID,
            requestFamily: requestFamily,
        )) ?? fallbackResolution
    }

    static func codexAttachmentPartResolution(
        snapshot: AiChatAttachmentSnapshot,
        fileIdentity: AiChatResolvedFileIdentity,
        provider: AiProvider,
        attachmentID: String,
    ) -> AiChatContextPartResolution {
        addingAttachmentID(
            to: .providerNativeFile(
                kind: .codexPathScope,
                mimeType: fileIdentity.mimeType,
                metadata: mergedResolutionMetadata(
                    snapshot.metadata,
                    displayPath: fileIdentity.displayPath,
                    mimeType: fileIdentity.mimeType,
                    provider: provider,
                ),
            ),
            attachmentID: attachmentID,
        )
    }

    static func nativeAttachmentPartResolution(
        _ input: AiChatAttachmentNativeResolutionInput,
    ) -> AiChatContextPartResolution? {
        let fileIdentity = input.fileIdentity
        let capability = AiChatProviderFileCapability.lookup(.init(
            provider: input.provider,
            rawModelID: input.rawModelID,
            requestFamily: providerRequestFamily(for: input.requestFamily),
            fileExtension: fileIdentity.fileExtension,
            detectedMIMEType: fileIdentity.mimeType,
            sizeBytes: fileIdentity.sizeBytes ?? 0,
            detectedContentTypeIdentifier: fileIdentity.contentTypeIdentifier,
        ))
        guard case let .providerNativeUpload(kind, normalizedMIMEType) = capability.disposition,
              let sizeBytes = fileIdentity.sizeBytes,
              sizeBytes > 0,
              sizeBytes <= AiChatProviderFileCapability.nativeUploadSafeLimitBytes,
              let fileURL = AiChatAttachmentResolverClient.attachmentResolutionURL(for: input.draft),
              let fileData = nativeUploadData(
                  fileURL: fileURL,
                  safeLimitBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes,
              )
        else {
            return nil
        }

        let metadata = nativeUploadMetadata(
            input: input,
            normalizedMIMEType: normalizedMIMEType,
            sizeBytes: sizeBytes,
            fileData: fileData,
        )
        return .providerNativeFile(kind: kind, mimeType: normalizedMIMEType, metadata: metadata)
    }

    static func nativeUploadMetadata(
        input: AiChatAttachmentNativeResolutionInput,
        normalizedMIMEType: String,
        sizeBytes: Int64,
        fileData: Data,
    ) -> [String: String] {
        let fileIdentity = input.fileIdentity
        var metadata = resolutionMetadata(from: input.fallbackResolution)
        for (key, value) in input.snapshot.metadata {
            metadata[key] = value
        }

        let base64Data = fileData.base64EncodedString()
        metadata["base64Data"] = base64Data
        metadata["nativeBase64Data"] = base64Data
        metadata["nativeUploadMode"] = "requestBase64"
        metadata["filename"] = fileIdentity.originalURL.lastPathComponent
        metadata["fileExtension"] = normalizedNonEmpty(fileIdentity.fileExtension) ?? fileIdentity.originalURL
            .pathExtension.lowercased()
        metadata["byteCount"] = "\(sizeBytes)"
        if let contentTypeIdentifier = normalizedNonEmpty(fileIdentity.contentTypeIdentifier) {
            metadata["contentTypeIdentifier"] = contentTypeIdentifier
        }

        return mergedResolutionMetadata(
            metadata,
            displayPath: fileIdentity.displayPath,
            mimeType: normalizedMIMEType,
            provider: input.provider,
        )
    }
}

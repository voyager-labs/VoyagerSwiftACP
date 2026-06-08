import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

struct AiChatContextResolveConfig {
    var provider: AiProvider
    var rawModelID: String
    var requestFamily: AiChatContextPartResolverRequestFamily
    var attachmentCanonicalPaths: Set<String>
    var fileManagerClient: FileManagerClient
}

extension AiChatContextPartResolverClient {
    static func resolveCurrentContext(
        _ snapshot: AiChatCurrentContextSnapshot,
        config: AiChatContextResolveConfig,
    ) -> AiChatResolvedCurrentContext {
        let references = snapshot.references.compactMap {
            resolveCurrentContextReference($0, config: config)
        }
        let items = snapshot.items.compactMap {
            resolveCurrentContextItem($0, config: config)
        }
        let attachments = snapshot.attachments.compactMap {
            resolveCurrentContextAttachment($0, config: config)
        }

        return AiChatResolvedCurrentContext(
            snapshot: AiChatCurrentContextSnapshot(
                summary: snapshot.summary,
                references: references.map(\.snapshotElement),
                items: items.map(\.snapshotElement),
                attachments: attachments.map(\.snapshotElement),
            ),
            parts: references.compactMap(\.part) + items.compactMap(\.part) + attachments.compactMap(\.part),
        )
    }

    static func resolveCurrentContextReference(
        _ reference: AiChatContextReference,
        config: AiChatContextResolveConfig,
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextReference>? {
        resolveCurrentContextElement(AiChatCurrentContextElementInput(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: reference.metadata,
            provider: config.provider,
            rawModelID: config.rawModelID,
            requestFamily: config.requestFamily,
            attachmentCanonicalPaths: config.attachmentCanonicalPaths,
            fileManagerClient: config.fileManagerClient,
        )) { identifier, subtitle, metadata in
            AiChatContextReference(
                kind: reference.kind,
                identifier: identifier,
                title: reference.title,
                subtitle: subtitle,
                metadata: metadata,
            )
        }
    }

    static func resolveCurrentContextItem(
        _ item: AiChatContextItem,
        config: AiChatContextResolveConfig,
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextItem>? {
        resolveCurrentContextElement(AiChatCurrentContextElementInput(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: item.metadata,
            provider: config.provider,
            rawModelID: config.rawModelID,
            requestFamily: config.requestFamily,
            attachmentCanonicalPaths: config.attachmentCanonicalPaths,
            fileManagerClient: config.fileManagerClient,
        )) { identifier, subtitle, metadata in
            AiChatContextItem(
                kind: item.kind,
                identifier: identifier,
                title: item.title,
                subtitle: subtitle,
                metadata: metadata,
                references: item.references.map {
                    let sanitizedMetadata = sanitizeContextMetadata($0.metadata, provider: provider)
                    return AiChatContextReference(
                        kind: $0.kind,
                        identifier: sanitizeContextScalar($0.identifier, provider: provider) ?? $0.identifier,
                        title: $0.title,
                        subtitle: sanitizeContextScalar($0.subtitle, provider: provider),
                        metadata: sanitizedMetadata,
                    )
                },
            )
        }
    }

    static func resolveCurrentContextAttachment(
        _ attachment: AiChatContextAttachment,
        config: AiChatContextResolveConfig,
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextAttachment>? {
        resolveCurrentContextElement(AiChatCurrentContextElementInput(
            kind: attachment.kind,
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            metadata: attachment.metadata,
            provider: config.provider,
            rawModelID: config.rawModelID,
            requestFamily: config.requestFamily,
            attachmentCanonicalPaths: config.attachmentCanonicalPaths,
            fileManagerClient: config.fileManagerClient,
        )) { identifier, subtitle, metadata in
            AiChatContextAttachment(
                identifier: identifier,
                title: attachment.title,
                subtitle: subtitle,
                kind: attachment.kind,
                metadata: metadata,
            )
        }
    }

    static func resolveCurrentContextElement<Element>(
        _ input: AiChatCurrentContextElementInput,
        builder: (String, String?, [String: String]) -> Element,
    ) -> AiChatCurrentContextElementDescriptor<Element>? {
        let fileIdentity = currentContextFileIdentity(
            identifier: input.identifier,
            subtitle: input.subtitle,
            metadata: input.metadata,
        )
        if let canonicalPath = fileIdentity?.canonicalURL.path(percentEncoded: false),
           input.attachmentCanonicalPaths.contains(canonicalPath)
        {
            return nil
        }

        let sanitizedMetadata = sanitizeContextMetadata(input.metadata, provider: input.provider)
        let sanitizedIdentifier = sanitizeContextScalar(input.identifier, provider: input.provider) ?? input.identifier
        let sanitizedSubtitle = sanitizeContextScalar(input.subtitle, provider: input.provider)
        let snapshotElement = builder(sanitizedIdentifier, sanitizedSubtitle, sanitizedMetadata)
        let part = makeCurrentContextPart(AiChatCurrentContextPartInput(
            kind: input.kind,
            title: input.title,
            metadata: sanitizedMetadata,
            provider: input.provider,
            rawModelID: input.rawModelID,
            requestFamily: input.requestFamily,
            fileIdentity: fileIdentity,
            fileManagerClient: input.fileManagerClient,
        ))
        return AiChatCurrentContextElementDescriptor(snapshotElement: snapshotElement, part: part)
    }

    static func makeCurrentContextPart(_ input: AiChatCurrentContextPartInput) -> AiChatResolvedContextPart? {
        guard let fileIdentity = input.fileIdentity else { return nil }

        let resolution = currentContextResolution(AiChatCurrentContextResolutionInput(
            kind: input.kind,
            metadata: input.metadata,
            provider: input.provider,
            rawModelID: input.rawModelID,
            requestFamily: input.requestFamily,
            fileIdentity: fileIdentity,
            fileManagerClient: input.fileManagerClient,
        ))
        let displayTitle = input.title ?? fileIdentity.originalURL.lastPathComponent
        return AiChatResolvedContextPart(
            source: .currentContext,
            resolution: resolution,
            fileKind: input.kind,
            canonicalPath: fileIdentity.canonicalURL.path(percentEncoded: false),
            displayPath: fileIdentity.displayPath,
            displayTitle: displayTitle,
            byteCount: fileIdentity.sizeBytes,
            mimeType: fileIdentity.mimeType,
        )
    }

    private static func currentContextResolution(_ input: AiChatCurrentContextResolutionInput)
        -> AiChatContextPartResolution
    {
        let baseMetadata = mergedResolutionMetadata(
            input.metadata,
            displayPath: input.fileIdentity.displayPath,
            mimeType: input.fileIdentity.mimeType,
            provider: input.provider,
        )

        if isReferenceOnlyCurrentContext(input) {
            return currentContextReferenceResolution(input, baseMetadata: baseMetadata)
        }

        if input.provider == .chatgptCodex {
            return .providerNativeFile(
                kind: .codexPathScope,
                mimeType: input.fileIdentity.mimeType,
                metadata: baseMetadata,
            )
        }

        return nativeCurrentContextResolution(input, baseMetadata: baseMetadata)
            ?? .referenceOnly(metadata: baseMetadata)
    }

    static func isReferenceOnlyCurrentContext(_ input: AiChatCurrentContextResolutionInput) -> Bool {
        input.fileIdentity.isDirectory || input.kind == .folder || input.fileIdentity.fileExtension == "voycoll"
    }

    static func currentContextReferenceResolution(
        _ input: AiChatCurrentContextResolutionInput,
        baseMetadata: [String: String],
    ) -> AiChatContextPartResolution {
        if input.fileIdentity.fileExtension == "voycoll" {
            var remainingBudget = AiChatAttachmentResolverClient.collectionItemPathUTF8ByteBudget
            return .referenceOnly(metadata: sanitizeContextMetadata(
                AiChatAttachmentResolverClient.collectionReferenceMetadata(
                    base: baseMetadata,
                    fileURL: input.fileIdentity.canonicalURL,
                    remainingTotalBudget: &remainingBudget,
                ),
                provider: input.provider,
            ))
        }

        let metadata = AiChatAttachmentResolverClient.folderStructureMetadata(
            base: baseMetadata,
            directoryURL: input.fileIdentity.canonicalURL,
            mode: AiChatAttachmentResolverClient.folderStructureMode(from: input.metadata),
            fileManagerClient: input.fileManagerClient,
        )
        return .referenceOnly(metadata: sanitizeContextMetadata(metadata, provider: input.provider))
    }

    static func nativeCurrentContextResolution(
        _ input: AiChatCurrentContextResolutionInput,
        baseMetadata: [String: String],
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
              let fileData = nativeUploadData(
                  fileURL: fileIdentity.originalURL,
                  safeLimitBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes,
              )
        else {
            return nil
        }

        let metadata = nativeCurrentContextMetadata(
            input,
            baseMetadata: baseMetadata,
            normalizedMIMEType: normalizedMIMEType,
            sizeBytes: sizeBytes,
            fileData: fileData,
        )
        return .providerNativeFile(kind: kind, mimeType: normalizedMIMEType, metadata: metadata)
    }

    static func nativeCurrentContextMetadata(
        _ input: AiChatCurrentContextResolutionInput,
        baseMetadata: [String: String],
        normalizedMIMEType: String,
        sizeBytes: Int64,
        fileData: Data,
    ) -> [String: String] {
        let fileIdentity = input.fileIdentity
        var nativeMetadata = baseMetadata
        let base64Data = fileData.base64EncodedString()
        nativeMetadata["base64Data"] = base64Data
        nativeMetadata["nativeBase64Data"] = base64Data
        nativeMetadata["nativeUploadMode"] = "requestBase64"
        nativeMetadata["filename"] = fileIdentity.originalURL.lastPathComponent
        nativeMetadata["fileExtension"] = normalizedNonEmpty(fileIdentity.fileExtension) ?? fileIdentity.originalURL
            .pathExtension.lowercased()
        nativeMetadata["byteCount"] = "\(sizeBytes)"
        if let contentTypeIdentifier = normalizedNonEmpty(fileIdentity.contentTypeIdentifier) {
            nativeMetadata["contentTypeIdentifier"] = contentTypeIdentifier
        }

        return mergedResolutionMetadata(
            nativeMetadata,
            displayPath: fileIdentity.displayPath,
            mimeType: normalizedMIMEType,
            provider: input.provider,
        )
    }

    static func currentContextFileIdentity(
        identifier: String,
        subtitle: String?,
        metadata: [String: String],
    ) -> AiChatResolvedFileIdentity? {
        for value in [metadata["path"], metadata["filePath"], subtitle, identifier].compactMap(\.self) {
            guard let trimmed = normalizedNonEmpty(value), trimmed.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: trimmed).standardizedFileURL
            if let identity = resolveFileIdentity(url) {
                return identity
            }
        }
        return nil
    }

    static func resolveFileIdentity(_ url: URL) -> AiChatResolvedFileIdentity? {
        let originalURL = url.standardizedFileURL
        let canonicalURL = originalURL.resolvingSymlinksInPath().standardizedFileURL
        guard let resourceValues = try? canonicalURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentTypeKey,
        ]) else {
            return nil
        }
        let contentType = resourceValues.contentType ?? UTType(filenameExtension: canonicalURL.pathExtension)
        let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
        let displayPath = displayPath(for: canonicalURL.path(percentEncoded: false), provider: .openai)
            ?? canonicalURL.lastPathComponent
        return AiChatResolvedFileIdentity(
            originalURL: originalURL,
            canonicalURL: canonicalURL,
            displayPath: displayPath,
            isDirectory: resourceValues.isDirectory == true,
            isRegularFile: resourceValues.isRegularFile == true,
            sizeBytes: resourceValues.totalFileAllocatedSize.map(Int64.init) ?? resourceValues.fileSize.map(Int64.init),
            mimeType: mimeType,
            contentTypeIdentifier: contentType?.identifier,
            fileExtension: canonicalURL.pathExtension,
        )
    }
}

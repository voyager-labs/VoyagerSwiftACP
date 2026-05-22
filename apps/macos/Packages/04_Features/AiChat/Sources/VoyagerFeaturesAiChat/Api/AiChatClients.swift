import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection

public struct AiChatExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest, StoredCredentialPayload?) -> AsyncStream<AiChatEvent>

    public init(execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) -> AsyncStream<AiChatEvent>) {
        self.execute = execute
    }

    public init(execute: @escaping @Sendable (AiChatRequest) -> AsyncStream<AiChatEvent>) {
        self.execute = { request, _ in execute(request) }
    }
}

extension AiChatExecutionClient: DependencyKey {
    public nonisolated static var liveValue: AiChatExecutionClient {
        live()
    }

    public nonisolated static var testValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _, _ in AsyncStream { $0.finish() } })
    }

    public nonisolated static var previewValue: AiChatExecutionClient {
        AiChatExecutionClient(execute: { _, _ in AsyncStream { $0.finish() } })
    }
}

public extension AiChatExecutionClient {
    nonisolated static func live(
        providerExecutionClient: VoyagerEntitiesAi.AiChatProviderExecutionClient = .liveValue,
    ) -> AiChatExecutionClient {
        AiChatExecutionClient(execute: { request, credential in
            let providerStream: AsyncThrowingStream<VoyagerEntitiesAi.AiChatProviderExecutionEvent, Error>
            do {
                providerStream = try providerExecutionClient.execute(request, credential)
            } catch {
                return immediateFailureStream(context: request.context, error: error)
            }

            return AsyncStream { continuation in
                let task = Task {
                    do {
                        for try await event in providerStream {
                            if Task.isCancelled {
                                break
                            }

                            switch event {
                            case .requestPrepared:
                                continue
                            case let .started(context):
                                continuation.yield(.started(context: context))
                            case let .delta(context, text):
                                continuation.yield(.delta(context: context, text: text))
                            case let .final(response):
                                continuation.yield(.final(response: response))
                            case let .failed(context, reason):
                                continuation.yield(.failed(context: context, reason: reason))
                            }
                        }
                    } catch {
                        if !Task.isCancelled {
                            continuation.yield(.failed(context: request.context, reason: mapExecutionError(error)))
                        }
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        })
    }
}

private extension AiChatExecutionClient {
    static func immediateFailureStream(
        context: AiChatRequestContextSnapshot,
        error: Error,
    ) -> AsyncStream<AiChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(context: context, reason: mapExecutionError(error)))
            continuation.finish()
        }
    }

    static func mapExecutionError(_ error: Error) -> AiChatExecutionFailure {
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? VoyagerEntitiesAi.AiChatProviderExecutionClientError {
            switch error {
            case .missingCredential, .invalidCredential:
                return .authentication
            case .unsupportedProvider:
                return .unsupportedProvider
            case .loweringFailed:
                return .invalidRequest
            }
        }
        return .unknown
    }
}

public extension DependencyValues {
    nonisolated var aiChatExecutionClient: AiChatExecutionClient {
        get { self[AiChatExecutionClient.self] }
        set { self[AiChatExecutionClient.self] = newValue }
    }
}


public enum AiChatContextPartResolverRequestFamily: String, Codable, Equatable, Sendable {
    case openAIResponses
    case anthropicMessages
    case codexCLI
}

public struct AiChatContextPartResolverInput: Equatable, Sendable {
    public let provider: AiProvider
    public let rawModelID: String
    public let requestFamily: AiChatContextPartResolverRequestFamily
    public let currentContext: AiChatCurrentContextSnapshot
    public let attachments: [AiChatAttachmentDraft]

    public init(
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        currentContext: AiChatCurrentContextSnapshot,
        attachments: [AiChatAttachmentDraft]
    ) {
        self.provider = provider
        self.rawModelID = rawModelID
        self.requestFamily = requestFamily
        self.currentContext = currentContext
        self.attachments = attachments
    }
}

public enum AiChatResolvedContextPartSource: String, Codable, Equatable, Sendable {
    case currentContext
    case attachment
}

public struct AiChatResolvedContextPart: Equatable, Sendable {
    public let source: AiChatResolvedContextPartSource
    public let resolution: AiChatContextPartResolution
    public let canonicalPath: String?
    public let displayPath: String?
    public let fileKind: AiChatContextItemKind
    public let displayTitle: String?
    public let byteCount: Int64?
    public let mimeType: String?

    public init(
        source: AiChatResolvedContextPartSource,
        resolution: AiChatContextPartResolution,
        canonicalPath: String? = nil,
        displayPath: String? = nil,
        fileKind: AiChatContextItemKind,
        displayTitle: String? = nil,
        byteCount: Int64? = nil,
        mimeType: String? = nil
    ) {
        self.source = source
        self.resolution = resolution
        self.canonicalPath = canonicalPath
        self.displayPath = displayPath
        self.fileKind = fileKind
        self.displayTitle = displayTitle
        self.byteCount = byteCount
        self.mimeType = mimeType
    }
}

public struct AiChatResolvedRequestContext: Equatable, Sendable {
    public let currentContext: AiChatCurrentContextSnapshot
    public let addedAttachments: [AiChatAttachmentSnapshot]
    public let parts: [AiChatResolvedContextPart]

    public init(
        currentContext: AiChatCurrentContextSnapshot,
        addedAttachments: [AiChatAttachmentSnapshot],
        parts: [AiChatResolvedContextPart]
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.parts = parts
    }
}

public struct AiChatContextPartResolverClient: Sendable {
    public var resolve: @Sendable (AiChatContextPartResolverInput) -> AiChatResolvedRequestContext

    public init(resolve: @escaping @Sendable (AiChatContextPartResolverInput) -> AiChatResolvedRequestContext) {
        self.resolve = resolve
    }
}

extension AiChatContextPartResolverClient: DependencyKey {
    public nonisolated static var liveValue: AiChatContextPartResolverClient {
        .live()
    }

    public nonisolated static var testValue: AiChatContextPartResolverClient {
        .live()
    }

    public nonisolated static var previewValue: AiChatContextPartResolverClient {
        .live()
    }
}

public extension AiChatContextPartResolverClient {
    nonisolated static func live() -> AiChatContextPartResolverClient {
        AiChatContextPartResolverClient { input in
            var remainingTotalBudget = AiChatAttachmentResolverClient.totalAttachmentTextUTF8ByteBudget
            let resolvedAttachments = input.attachments.map { attachment in
                let result = AiChatAttachmentResolverClient.resolveAttachment(
                    attachment,
                    remainingTotalBudget: &remainingTotalBudget
                )
                return AiChatAttachmentSnapshot(
                    id: attachment.id,
                    source: attachment.source,
                    displayTitle: attachment.displayTitle,
                    subtitle: attachment.subtitle,
                    kind: attachment.kind,
                    sourceLocation: attachment.sourceLocation,
                    metadata: attachment.metadata,
                    resolutionResult: result
                )
            }

            let attachmentDescriptors = zip(input.attachments, resolvedAttachments).map {
                makeAttachmentDescriptor(
                    draft: $0.0,
                    snapshot: $0.1,
                    provider: input.provider,
                    rawModelID: input.rawModelID,
                    requestFamily: input.requestFamily
                )
            }
            let attachmentCanonicalPaths = Set(attachmentDescriptors.compactMap(\.part.canonicalPath))

            let currentContextResolution = resolveCurrentContext(
                input.currentContext,
                provider: input.provider,
                rawModelID: input.rawModelID,
                requestFamily: input.requestFamily,
                attachmentCanonicalPaths: attachmentCanonicalPaths
            )

            let sanitizedAttachments = attachmentDescriptors.map { $0.snapshot }
            let parts = attachmentDescriptors.map { $0.part } + currentContextResolution.parts
            return AiChatResolvedRequestContext(
                currentContext: currentContextResolution.snapshot,
                addedAttachments: sanitizedAttachments,
                parts: parts
            )
        }
    }
}

public extension DependencyValues {
    nonisolated var aiChatContextPartResolverClient: AiChatContextPartResolverClient {
        get { self[AiChatContextPartResolverClient.self] }
        set { self[AiChatContextPartResolverClient.self] = newValue }
    }
}

public struct AiChatAttachmentResolverClient: Sendable {
    public var resolve: @Sendable ([AiChatAttachmentDraft]) -> [AiChatAttachmentSnapshot]

    public init(resolve: @escaping @Sendable ([AiChatAttachmentDraft]) -> [AiChatAttachmentSnapshot]) {
        self.resolve = resolve
    }
}

extension AiChatAttachmentResolverClient: DependencyKey {
    public nonisolated static var liveValue: AiChatAttachmentResolverClient {
        .live()
    }

    public nonisolated static var testValue: AiChatAttachmentResolverClient {
        .live()
    }

    public nonisolated static var previewValue: AiChatAttachmentResolverClient {
        .live()
    }
}

public extension AiChatAttachmentResolverClient {
    nonisolated static func live() -> AiChatAttachmentResolverClient {
        AiChatAttachmentResolverClient { attachments in
            let result = AiChatContextPartResolverClient.live().resolve(
                AiChatContextPartResolverInput(
                    provider: AiProvider.openai,
                    rawModelID: "",
                    requestFamily: .openAIResponses,
                    currentContext: AiChatCurrentContextSnapshot(),
                    attachments: attachments
                )
            )
            return result.addedAttachments
        }
    }
}

private extension AiChatAttachmentResolverClient {
    static func resolveAttachment(
        _ attachment: AiChatAttachmentDraft,
        remainingTotalBudget: inout Int
    ) -> AiChatAttachmentResolutionResult {
        guard remainingTotalBudget > 0 else {
            return .failure(reason: .tooLarge, metadata: attachmentResolutionMetadata(for: attachment))
        }

        if attachment.source == .folder {
            let metadata = directoryReferenceMetadata(
                base: attachmentResolutionMetadata(for: attachment),
                directoryURL: attachmentResolutionURL(for: attachment)
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
            let metadata = directoryReferenceMetadata(
                base: attachmentResolutionMetadata(for: attachment),
                directoryURL: fileURL
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
            remainingTotalBudget: &remainingTotalBudget
        )
    }


    static func resolveCollectionAttachment(
        _ attachment: AiChatAttachmentDraft,
        remainingTotalBudget: inout Int
    ) -> AiChatAttachmentResolutionResult {
        let metadata = collectionReferenceMetadata(
            base: attachmentResolutionMetadata(for: attachment),
            fileURL: attachmentResolutionURL(for: attachment),
            remainingTotalBudget: &remainingTotalBudget
        )
        return .resolvedReference(metadata: metadata)
    }

    static func collectionReferenceMetadata(
        base: [String: String],
        fileURL: URL?,
        remainingTotalBudget: inout Int
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
                budget: min(collectionItemPathUTF8ByteBudget, remainingTotalBudget)
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
        budget: Int
    ) -> (paths: [String], utf8Bytes: Int, truncated: Bool) {
        var includedPaths: [String] = []
        var usedBytes = 0

        for path in paths {
            let separatorBytes = includedPaths.isEmpty ? 0 : 1
            let pathBytes = path.utf8.count
            guard usedBytes + separatorBytes + pathBytes <= budget else {
                return (includedPaths, usedBytes, true)
            }
            includedPaths.append(path)
            usedBytes += separatorBytes + pathBytes
        }

        return (includedPaths, usedBytes, false)
    }

    static func resolveFileAttachment(
        _ attachment: AiChatAttachmentDraft,
        fileURL: URL,
        relativePath: String,
        remainingTotalBudget: inout Int
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
        remainingTotalBudget: inout Int
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
            guard let text = String(data: Data(selectedData), encoding: .utf8) else {
                return .failure(.unsupportedType)
            }
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return .failure(.emptyContent) }
            remainingTotalBudget -= selectedData.count
            return .success(text: normalizedText, truncated: truncated)
        } catch CocoaError.fileReadNoPermission {
            return .failure(.permissionDenied)
        } catch {
            return .failure(.readFailed)
        }
    }


    static func directoryReferenceMetadata(base: [String: String], directoryURL: URL?) -> [String: String] {
        var metadata = base
        guard let directoryURL else { return metadata }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let limit = 80
            let paths = sorted.prefix(limit).map { $0.path(percentEncoded: false) }
            metadata["collectionItemCount"] = "\(urls.count)"
            metadata["collectionItemsIncluded"] = "\(paths.count)"
            metadata["collectionItemsTruncated"] = urls.count > limit ? "true" : "false"
            if !paths.isEmpty {
                metadata["collectionItemPaths"] = paths.joined(separator: "\n")
            }
        } catch {
            metadata["collectionSnapshotStatus"] = CollectionFileReferenceSnapshotStatus.missing.rawValue
        }
        return metadata
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

private struct AiChatResolvedAttachmentDescriptor {
    let snapshot: AiChatAttachmentSnapshot
    let part: AiChatResolvedContextPart
}

private struct AiChatResolvedCurrentContext {
    let snapshot: AiChatCurrentContextSnapshot
    let parts: [AiChatResolvedContextPart]
}

private struct AiChatCurrentContextElementDescriptor<Element> {
    let snapshotElement: Element
    let part: AiChatResolvedContextPart?
}

private struct AiChatResolvedFileIdentity {
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

private extension AiChatContextPartResolverClient {
    static func makeAttachmentDescriptor(
        draft: AiChatAttachmentDraft,
        snapshot: AiChatAttachmentSnapshot,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily
    ) -> AiChatResolvedAttachmentDescriptor {
        let fileIdentity = AiChatAttachmentResolverClient.attachmentResolutionURL(for: draft).flatMap(resolveFileIdentity)
        let sanitizedSnapshot = sanitizeAttachmentSnapshot(snapshot, provider: provider, displayPath: fileIdentity?.displayPath)
        let part = AiChatResolvedContextPart(
            source: .attachment,
            resolution: attachmentPartResolution(
                draft: draft,
                snapshot: sanitizedSnapshot,
                fileIdentity: fileIdentity,
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily
            ),
            canonicalPath: fileIdentity?.canonicalURL.path(percentEncoded: false),
            displayPath: fileIdentity?.displayPath,
            fileKind: draft.kind,
            displayTitle: sanitizedSnapshot.displayTitle,
            byteCount: fileIdentity?.sizeBytes,
            mimeType: fileIdentity?.mimeType
        )
        return AiChatResolvedAttachmentDescriptor(snapshot: sanitizedSnapshot, part: part)
    }

    static func attachmentPartResolution(
        draft: AiChatAttachmentDraft,
        snapshot: AiChatAttachmentSnapshot,
        fileIdentity: AiChatResolvedFileIdentity?,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily
    ) -> AiChatContextPartResolution {
        let fallbackResolution = addingAttachmentID(
            to: Self.sanitizeContextPartResolution(
                from: snapshot.resolutionResult.contextPartResolution,
                provider: provider
            ),
            attachmentID: draft.id.rawValue
        )
        guard draft.source == .file,
              let fileIdentity,
              fileIdentity.isRegularFile,
              !fileIdentity.isDirectory
        else {
            return fallbackResolution
        }

        if provider == .chatgptCodex {
            return addingAttachmentID(
                to: .providerNativeFile(
                    kind: .codexPathScope,
                    mimeType: fileIdentity.mimeType,
                    metadata: mergedResolutionMetadata(
                        snapshot.metadata,
                        displayPath: fileIdentity.displayPath,
                        mimeType: fileIdentity.mimeType,
                        provider: provider
                    )
                ),
                attachmentID: draft.id.rawValue
            )
        }

        let capability = AiChatProviderFileCapability.lookup(.init(
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: providerRequestFamily(for: requestFamily),
            fileExtension: fileIdentity.fileExtension,
            detectedMIMEType: fileIdentity.mimeType,
            detectedContentTypeIdentifier: fileIdentity.contentTypeIdentifier,
            sizeBytes: fileIdentity.sizeBytes ?? 0
        ))
        guard case let .providerNativeUpload(kind, normalizedMIMEType) = capability.disposition,
              let sizeBytes = fileIdentity.sizeBytes,
              sizeBytes > 0,
              sizeBytes <= AiChatProviderFileCapability.nativeUploadSafeLimitBytes,
              let fileURL = AiChatAttachmentResolverClient.attachmentResolutionURL(for: draft),
              let fileData = nativeUploadData(fileURL: fileURL, safeLimitBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes)
        else {
            return fallbackResolution
        }

        var metadata = resolutionMetadata(from: fallbackResolution)
        for (key, value) in snapshot.metadata {
            metadata[key] = value
        }

        let base64Data = fileData.base64EncodedString()
        metadata["base64Data"] = base64Data
        metadata["nativeBase64Data"] = base64Data
        metadata["nativeUploadMode"] = "requestBase64"
        metadata["filename"] = fileIdentity.originalURL.lastPathComponent
        metadata["fileExtension"] = normalizedNonEmpty(fileIdentity.fileExtension) ?? fileIdentity.originalURL.pathExtension.lowercased()
        metadata["byteCount"] = "\(sizeBytes)"
        if let contentTypeIdentifier = normalizedNonEmpty(fileIdentity.contentTypeIdentifier) {
            metadata["contentTypeIdentifier"] = contentTypeIdentifier
        }

        return .providerNativeFile(
            kind: kind,
            mimeType: normalizedMIMEType,
            metadata: mergedResolutionMetadata(
                metadata,
                displayPath: fileIdentity.displayPath,
                mimeType: normalizedMIMEType,
                provider: provider
            )
        )
    }

    static func resolveCurrentContext(
        _ snapshot: AiChatCurrentContextSnapshot,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        attachmentCanonicalPaths: Set<String>
    ) -> AiChatResolvedCurrentContext {
        let references = snapshot.references.compactMap {
            resolveCurrentContextReference(
                $0,
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                attachmentCanonicalPaths: attachmentCanonicalPaths
            )
        }
        let items = snapshot.items.compactMap {
            resolveCurrentContextItem(
                $0,
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                attachmentCanonicalPaths: attachmentCanonicalPaths
            )
        }
        let attachments = snapshot.attachments.compactMap {
            resolveCurrentContextAttachment(
                $0,
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                attachmentCanonicalPaths: attachmentCanonicalPaths
            )
        }

        return AiChatResolvedCurrentContext(
            snapshot: AiChatCurrentContextSnapshot(
                summary: snapshot.summary,
                references: references.map { $0.snapshotElement },
                items: items.map { $0.snapshotElement },
                attachments: attachments.map { $0.snapshotElement }
            ),
            parts: references.compactMap { $0.part } + items.compactMap { $0.part } + attachments.compactMap { $0.part }
        )
    }

    static func resolveCurrentContextReference(
        _ reference: AiChatContextReference,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        attachmentCanonicalPaths: Set<String>
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextReference>? {
        resolveCurrentContextElement(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: reference.metadata,
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: requestFamily,
            attachmentCanonicalPaths: attachmentCanonicalPaths
        ) { identifier, subtitle, metadata in
            AiChatContextReference(
                kind: reference.kind,
                identifier: identifier,
                title: reference.title,
                subtitle: subtitle,
                metadata: metadata
            )
        }
    }

    static func resolveCurrentContextItem(
        _ item: AiChatContextItem,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        attachmentCanonicalPaths: Set<String>
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextItem>? {
        resolveCurrentContextElement(
            kind: item.kind,
            identifier: item.identifier,
            title: item.title,
            subtitle: item.subtitle,
            metadata: item.metadata,
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: requestFamily,
            attachmentCanonicalPaths: attachmentCanonicalPaths
        ) { identifier, subtitle, metadata in
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
                        metadata: sanitizedMetadata
                    )
                }
            )
        }
    }

    static func resolveCurrentContextAttachment(
        _ attachment: AiChatContextAttachment,
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        attachmentCanonicalPaths: Set<String>
    ) -> AiChatCurrentContextElementDescriptor<AiChatContextAttachment>? {
        resolveCurrentContextElement(
            kind: attachment.kind,
            identifier: attachment.identifier,
            title: attachment.title,
            subtitle: attachment.subtitle,
            metadata: attachment.metadata,
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: requestFamily,
            attachmentCanonicalPaths: attachmentCanonicalPaths
        ) { identifier, subtitle, metadata in
            AiChatContextAttachment(
                identifier: identifier,
                title: attachment.title,
                subtitle: subtitle,
                kind: attachment.kind,
                metadata: metadata
            )
        }
    }

    static func resolveCurrentContextElement<Element>(
        kind: AiChatContextItemKind,
        identifier: String,
        title: String?,
        subtitle: String?,
        metadata: [String: String],
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        attachmentCanonicalPaths: Set<String>,
        builder: (String, String?, [String: String]) -> Element
    ) -> AiChatCurrentContextElementDescriptor<Element>? {
        let fileIdentity = currentContextFileIdentity(
            identifier: identifier,
            subtitle: subtitle,
            metadata: metadata
        )
        if let canonicalPath = fileIdentity?.canonicalURL.path(percentEncoded: false),
           attachmentCanonicalPaths.contains(canonicalPath)
        {
            return nil
        }

        let sanitizedMetadata = sanitizeContextMetadata(metadata, provider: provider)
        let sanitizedIdentifier = sanitizeContextScalar(identifier, provider: provider) ?? identifier
        let sanitizedSubtitle = sanitizeContextScalar(subtitle, provider: provider)
        let snapshotElement = builder(sanitizedIdentifier, sanitizedSubtitle, sanitizedMetadata)
        let part = makeCurrentContextPart(
            kind: kind,
            title: title,
            metadata: sanitizedMetadata,
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: requestFamily,
            fileIdentity: fileIdentity
        )
        return AiChatCurrentContextElementDescriptor(snapshotElement: snapshotElement, part: part)
    }

    static func makeCurrentContextPart(
        kind: AiChatContextItemKind,
        title: String?,
        metadata: [String: String],
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        fileIdentity: AiChatResolvedFileIdentity?
    ) -> AiChatResolvedContextPart? {
        guard let fileIdentity else { return nil }

        let resolution = currentContextResolution(
            kind: kind,
            metadata: metadata,
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: requestFamily,
            fileIdentity: fileIdentity
        )
        let displayTitle = title ?? fileIdentity.originalURL.lastPathComponent
        return AiChatResolvedContextPart(
            source: .currentContext,
            resolution: resolution,
            canonicalPath: fileIdentity.canonicalURL.path(percentEncoded: false),
            displayPath: fileIdentity.displayPath,
            fileKind: kind,
            displayTitle: displayTitle,
            byteCount: fileIdentity.sizeBytes,
            mimeType: fileIdentity.mimeType
        )
    }

    static func currentContextResolution(
        kind: AiChatContextItemKind,
        metadata: [String: String],
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatContextPartResolverRequestFamily,
        fileIdentity: AiChatResolvedFileIdentity
    ) -> AiChatContextPartResolution {
        let baseMetadata = mergedResolutionMetadata(
            metadata,
            displayPath: fileIdentity.displayPath,
            mimeType: fileIdentity.mimeType,
            provider: provider
        )

        if fileIdentity.isDirectory || kind == .folder || fileIdentity.fileExtension == "voycoll" {
            var remainingBudget = AiChatAttachmentResolverClient.collectionItemPathUTF8ByteBudget
            let metadata: [String: String]
            if fileIdentity.fileExtension == "voycoll" {
                metadata = sanitizeContextMetadata(
                    AiChatAttachmentResolverClient.collectionReferenceMetadata(
                        base: baseMetadata,
                        fileURL: fileIdentity.canonicalURL,
                        remainingTotalBudget: &remainingBudget
                    ),
                    provider: provider
                )
            } else {
                metadata = AiChatAttachmentResolverClient.directoryReferenceMetadata(
                    base: baseMetadata,
                    directoryURL: fileIdentity.canonicalURL
                )
            }
            return .referenceOnly(metadata: metadata)
        }

        if provider == .chatgptCodex {
            return .providerNativeFile(
                kind: .codexPathScope,
                mimeType: fileIdentity.mimeType,
                metadata: baseMetadata
            )
        }

        let capability = AiChatProviderFileCapability.lookup(.init(
            provider: provider,
            rawModelID: rawModelID,
            requestFamily: providerRequestFamily(for: requestFamily),
            fileExtension: fileIdentity.fileExtension,
            detectedMIMEType: fileIdentity.mimeType,
            detectedContentTypeIdentifier: fileIdentity.contentTypeIdentifier,
            sizeBytes: fileIdentity.sizeBytes ?? 0
        ))
        guard case let .providerNativeUpload(kind, normalizedMIMEType) = capability.disposition,
              let sizeBytes = fileIdentity.sizeBytes,
              sizeBytes > 0,
              sizeBytes <= AiChatProviderFileCapability.nativeUploadSafeLimitBytes,
              let fileData = nativeUploadData(fileURL: fileIdentity.originalURL, safeLimitBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes)
        else {
            return .referenceOnly(metadata: baseMetadata)
        }

        var nativeMetadata = baseMetadata
        let base64Data = fileData.base64EncodedString()
        nativeMetadata["base64Data"] = base64Data
        nativeMetadata["nativeBase64Data"] = base64Data
        nativeMetadata["nativeUploadMode"] = "requestBase64"
        nativeMetadata["filename"] = fileIdentity.originalURL.lastPathComponent
        nativeMetadata["fileExtension"] = normalizedNonEmpty(fileIdentity.fileExtension) ?? fileIdentity.originalURL.pathExtension.lowercased()
        nativeMetadata["byteCount"] = "\(sizeBytes)"
        if let contentTypeIdentifier = normalizedNonEmpty(fileIdentity.contentTypeIdentifier) {
            nativeMetadata["contentTypeIdentifier"] = contentTypeIdentifier
        }

        return .providerNativeFile(
            kind: kind,
            mimeType: normalizedMIMEType,
            metadata: mergedResolutionMetadata(
                nativeMetadata,
                displayPath: fileIdentity.displayPath,
                mimeType: normalizedMIMEType,
                provider: provider
            )
        )
    }

    static func currentContextFileIdentity(
        identifier: String,
        subtitle: String?,
        metadata: [String: String]
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
        let resourceValues = try? canonicalURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentTypeKey,
        ])
        let contentType = resourceValues?.contentType ?? UTType(filenameExtension: canonicalURL.pathExtension)
        let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
        let displayPath = displayPath(for: canonicalURL.path(percentEncoded: false), provider: .openai)
            ?? canonicalURL.lastPathComponent
        return AiChatResolvedFileIdentity(
            originalURL: originalURL,
            canonicalURL: canonicalURL,
            displayPath: displayPath,
            isDirectory: resourceValues?.isDirectory == true,
            isRegularFile: resourceValues?.isRegularFile != false,
            sizeBytes: resourceValues?.totalFileAllocatedSize.map(Int64.init) ?? resourceValues?.fileSize.map(Int64.init),
            mimeType: mimeType,
            contentTypeIdentifier: contentType?.identifier,
            fileExtension: canonicalURL.pathExtension
        )
    }

    static func sanitizeAttachmentSnapshot(
        _ snapshot: AiChatAttachmentSnapshot,
        provider: AiProvider,
        displayPath: String?
    ) -> AiChatAttachmentSnapshot {
        let sanitizedLocation = sanitizeSourceLocation(
            snapshot.sourceLocation,
            provider: provider,
            displayPath: displayPath
        )
        return AiChatAttachmentSnapshot(
            id: snapshot.id,
            source: snapshot.source,
            displayTitle: snapshot.displayTitle,
            subtitle: sanitizeContextScalar(snapshot.subtitle, provider: provider),
            kind: snapshot.kind,
            sourceLocation: sanitizedLocation,
            metadata: sanitizeContextMetadata(snapshot.metadata, provider: provider),
            resolutionResult: sanitizeResolutionResult(snapshot.resolutionResult, provider: provider)
        )
    }

    static func sanitizeResolutionResult(
        _ resolutionResult: AiChatAttachmentResolutionResult,
        provider: AiProvider
    ) -> AiChatAttachmentResolutionResult {
        switch resolutionResult {
        case let .resolvedText(text, metadata):
            return .resolvedText(text: text, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .resolvedReference(metadata):
            return .resolvedReference(metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .resolvedPartial(text, truncated, metadata):
            return .resolvedPartial(
                text: text,
                truncated: truncated,
                metadata: sanitizeContextMetadata(metadata, provider: provider)
            )
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: sanitizeContextMetadata(metadata, provider: provider))
        }
    }

    static func sanitizeSourceLocation(
        _ sourceLocation: AiChatAttachmentSourceLocation,
        provider: AiProvider,
        displayPath redactedPath: String?
    ) -> AiChatAttachmentSourceLocation {
        guard provider != .chatgptCodex else { return sourceLocation }
        let path = redactedPath
            ?? displayPath(for: sourceLocation.filePath, provider: provider)
            ?? displayPath(for: sourceLocation.fileURL?.path(percentEncoded: false), provider: provider)
        return AiChatAttachmentSourceLocation(fileURL: nil, filePath: path)
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
        for requestFamily: AiChatContextPartResolverRequestFamily
    ) -> AiChatProviderRequestFamily {
        switch requestFamily {
        case .openAIResponses:
            return .openAIResponses
        case .anthropicMessages:
            return .anthropicMessages
        case .codexCLI:
            return .codexCLI
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
            return metadata
        }
    }

    static func addingAttachmentID(
        to resolution: AiChatContextPartResolution,
        attachmentID: String
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
        provider: AiProvider
    ) -> AiChatContextPartResolution {
        switch resolution {
        case let .inlineText(text, metadata):
            return .inlineText(text: text, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .partialText(text, truncated, metadata):
            return .partialText(text: text, truncated: truncated, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .referenceOnly(metadata):
            return .referenceOnly(metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .collectionPathList(paths, metadata):
            let sanitizedPaths = provider == .chatgptCodex ? paths : paths.compactMap { sanitizeContextScalar($0, provider: provider) }
            return .collectionPathList(paths: sanitizedPaths, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .providerNativeFile(kind, mimeType, metadata):
            return .providerNativeFile(kind: kind, mimeType: mimeType, metadata: sanitizeContextMetadata(metadata, provider: provider))
        case let .failure(reason, metadata):
            return .failure(reason: reason, metadata: sanitizeContextMetadata(metadata, provider: provider))
        }
    }

    static func mergedResolutionMetadata(
        _ metadata: [String: String],
        displayPath: String?,
        mimeType: String?,
        provider: AiProvider
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
        guard let value = value else { return nil }
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

public extension DependencyValues {
    nonisolated var aiChatAttachmentResolverClient: AiChatAttachmentResolverClient {
        get { self[AiChatAttachmentResolverClient.self] }
        set { self[AiChatAttachmentResolverClient.self] = newValue }
    }
}

public struct AiChatSessionPersistenceClient: Sendable {
    public var loadSession: @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?
    public var saveSession: @Sendable (AiChatSessionSnapshot) async throws -> Void
    public var deleteSession: @Sendable (AiChatSessionID) async throws -> Void

    public init(
        loadSession: @escaping @Sendable (AiChatSessionID) async throws -> AiChatSessionSnapshot?,
        saveSession: @escaping @Sendable (AiChatSessionSnapshot) async throws -> Void,
        deleteSession: @escaping @Sendable (AiChatSessionID) async throws -> Void,
    ) {
        self.loadSession = loadSession
        self.saveSession = saveSession
        self.deleteSession = deleteSession
    }
}

extension AiChatSessionPersistenceClient: DependencyKey {
    public nonisolated static var liveValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }

    public nonisolated static var testValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }

    public nonisolated static var previewValue: AiChatSessionPersistenceClient {
        AiChatSessionPersistenceClient(
            loadSession: { _ in nil },
            saveSession: { _ in },
            deleteSession: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiChatSessionPersistenceClient: AiChatSessionPersistenceClient {
        get { self[AiChatSessionPersistenceClient.self] }
        set { self[AiChatSessionPersistenceClient.self] = newValue }
    }
}

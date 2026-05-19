import ComposableArchitecture
import Foundation
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
            var remainingTotalBudget = totalAttachmentTextUTF8ByteBudget
            return attachments.map { attachment in
                let result = resolveAttachment(attachment, remainingTotalBudget: &remainingTotalBudget)
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
            return .resolvedReference(metadata: attachmentResolutionMetadata(for: attachment))
        }

        if attachment.source == .collectionDocument || attachment.source == .collectionFile {
            return resolveCollectionAttachment(attachment, remainingTotalBudget: &remainingTotalBudget)
        }

        guard let fileURL = attachmentResolutionURL(for: attachment) else {
            return .failure(reason: .brokenReference, metadata: attachmentResolutionMetadata(for: attachment))
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if resourceValues?.isDirectory == true {
            return .resolvedReference(metadata: attachmentResolutionMetadata(for: attachment))
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
        var metadata = attachmentResolutionMetadata(for: attachment)
        guard let fileURL = attachmentResolutionURL(for: attachment) else {
            metadata["collectionSnapshotStatus"] = CollectionFileReferenceSnapshotStatus.missing.rawValue
            return .resolvedReference(metadata: metadata)
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
        return .resolvedReference(metadata: metadata)
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
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return .failure(.emptyContent) }
            let allowedBytes = min(perAttachmentUTF8ByteBudget, remainingTotalBudget)
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

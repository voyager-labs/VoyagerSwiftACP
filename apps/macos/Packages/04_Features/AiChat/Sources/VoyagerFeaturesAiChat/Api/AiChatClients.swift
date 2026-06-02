import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared

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
        attachments: [AiChatAttachmentDraft],
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
        fileKind: AiChatContextItemKind,
        canonicalPath: String? = nil,
        displayPath: String? = nil,
        displayTitle: String? = nil,
        byteCount: Int64? = nil,
        mimeType: String? = nil,
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
        parts: [AiChatResolvedContextPart],
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.parts = parts
    }
}

public struct AiChatContextPartResolverClient: Sendable {
    public var resolve: @Sendable (AiChatContextPartResolverInput) async -> AiChatResolvedRequestContext

    public init(resolve: @escaping @Sendable (AiChatContextPartResolverInput) async -> AiChatResolvedRequestContext) {
        self.resolve = resolve
    }
}

extension AiChatContextPartResolverClient: DependencyKey {
    public nonisolated static var liveValue: AiChatContextPartResolverClient {
        .live(fileManagerClient: .liveValue)
    }

    public nonisolated static var testValue: AiChatContextPartResolverClient {
        .live()
    }

    public nonisolated static var previewValue: AiChatContextPartResolverClient {
        .live()
    }
}

struct AiChatAttachmentNativeResolutionInput {
    var draft: AiChatAttachmentDraft
    var snapshot: AiChatAttachmentSnapshot
    var fallbackResolution: AiChatContextPartResolution
    var fileIdentity: AiChatResolvedFileIdentity
    var provider: AiProvider
    var rawModelID: String
    var requestFamily: AiChatContextPartResolverRequestFamily
}

struct AiChatCurrentContextResolutionInput {
    var kind: AiChatContextItemKind
    var metadata: [String: String]
    var provider: AiProvider
    var rawModelID: String
    var requestFamily: AiChatContextPartResolverRequestFamily
    var fileIdentity: AiChatResolvedFileIdentity
    var fileManagerClient: FileManagerClient
}

struct AiChatCurrentContextElementInput {
    var kind: AiChatContextItemKind
    var identifier: String
    var title: String?
    var subtitle: String?
    var metadata: [String: String]
    var provider: AiProvider
    var rawModelID: String
    var requestFamily: AiChatContextPartResolverRequestFamily
    var attachmentCanonicalPaths: Set<String>
    var fileManagerClient: FileManagerClient
}

struct AiChatCurrentContextPartInput {
    var kind: AiChatContextItemKind
    var title: String?
    var metadata: [String: String]
    var provider: AiProvider
    var rawModelID: String
    var requestFamily: AiChatContextPartResolverRequestFamily
    var fileIdentity: AiChatResolvedFileIdentity?
    var fileManagerClient: FileManagerClient
}

public extension AiChatContextPartResolverClient {
    nonisolated static func live(
        fileManagerClient: FileManagerClient = .liveValue,
    ) -> AiChatContextPartResolverClient {
        AiChatContextPartResolverClient { input in
            await Task.detached(priority: .userInitiated) {
                resolveSynchronously(input: input, fileManagerClient: fileManagerClient)
            }.value
        }
    }

    static func resolveSynchronously(
        input: AiChatContextPartResolverInput,
        fileManagerClient: FileManagerClient,
    ) -> AiChatResolvedRequestContext {
        var remainingTotalBudget = AiChatAttachmentResolverClient.totalAttachmentTextUTF8ByteBudget
        let resolvedAttachments = input.attachments.map { attachment in
            let result = AiChatAttachmentResolverClient.resolveAttachment(
                attachment,
                remainingTotalBudget: &remainingTotalBudget,
                fileManagerClient: fileManagerClient,
            )
            return AiChatAttachmentSnapshot(
                id: attachment.id,
                source: attachment.source,
                displayTitle: attachment.displayTitle,
                subtitle: attachment.subtitle,
                kind: attachment.kind,
                sourceLocation: attachment.sourceLocation,
                metadata: attachment.metadata,
                resolutionResult: result,
            )
        }

        let attachmentDescriptors = zip(input.attachments, resolvedAttachments).map {
            makeAttachmentDescriptor(
                draft: $0.0,
                snapshot: $0.1,
                provider: input.provider,
                rawModelID: input.rawModelID,
                requestFamily: input.requestFamily,
                fileManagerClient: fileManagerClient,
            )
        }
        let attachmentCanonicalPaths = Set(attachmentDescriptors.compactMap(\.part.canonicalPath))

        let currentContextResolution = resolveCurrentContext(
            input.currentContext,
            provider: input.provider,
            rawModelID: input.rawModelID,
            requestFamily: input.requestFamily,
            attachmentCanonicalPaths: attachmentCanonicalPaths,
            fileManagerClient: fileManagerClient,
        )

        let sanitizedAttachments = attachmentDescriptors.map(\.snapshot)
        let parts = attachmentDescriptors.map(\.part) + currentContextResolution.parts
        return AiChatResolvedRequestContext(
            currentContext: currentContextResolution.snapshot,
            addedAttachments: sanitizedAttachments,
            parts: parts,
        )
    }
}

public extension DependencyValues {
    nonisolated var aiChatContextPartResolverClient: AiChatContextPartResolverClient {
        get { self[AiChatContextPartResolverClient.self] }
        set { self[AiChatContextPartResolverClient.self] = newValue }
    }
}

public struct AiChatAttachmentResolverClient: Sendable {
    public var resolve: @Sendable ([AiChatAttachmentDraft]) async -> [AiChatAttachmentSnapshot]

    public init(resolve: @escaping @Sendable ([AiChatAttachmentDraft]) async -> [AiChatAttachmentSnapshot]) {
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
            let result = await AiChatContextPartResolverClient.live().resolve(
                AiChatContextPartResolverInput(
                    provider: AiProvider.openai,
                    rawModelID: "",
                    requestFamily: .openAIResponses,
                    currentContext: AiChatCurrentContextSnapshot(),
                    attachments: attachments,
                ),
            )
            return result.addedAttachments
        }
    }
}

public extension DependencyValues {
    nonisolated var aiChatSessionPersistenceClient: AiChatSessionPersistenceClient {
        get { self[AiChatSessionPersistenceClient.self] }
        set { self[AiChatSessionPersistenceClient.self] = newValue }
    }
}

func decodeUTF8Prefix(_ data: Data) -> (text: String, byteCount: Int)? {
    var selectedData = data
    while !selectedData.isEmpty {
        if let text = String(data: selectedData, encoding: .utf8) {
            return (text, selectedData.count)
        }
        selectedData.removeLast()
    }
    return nil
}

import Foundation

public struct AiChatSessionID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatRequestID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatRunID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatAttachmentID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AiModelHandle: Codable, Equatable, Hashable, Sendable {
    public let provider: AiProvider
    public let rawValue: String

    public init(provider: AiProvider, rawValue: String) {
        self.provider = provider
        self.rawValue = rawValue
    }
}

public struct AiModelCatalogRow: Codable, Equatable, Sendable {
    public let handle: AiModelHandle
    public let displayName: String
    public let authMethod: ProviderAuthMethod
    public let subtitle: String?
    public let sortOrder: Int
    public let isDefault: Bool
    public let isRecommended: Bool

    // swiftlint:disable function_default_parameter_at_end
    public init(
        handle: AiModelHandle,
        displayName: String,
        authMethod: ProviderAuthMethod,
        subtitle: String? = nil,
        sortOrder: Int,
        isDefault: Bool = false,
        isRecommended: Bool = false,
    ) {
        self.handle = handle
        self.displayName = displayName
        self.authMethod = authMethod
        self.subtitle = subtitle
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isRecommended = isRecommended
    }
    // swiftlint:enable function_default_parameter_at_end
}

public enum AiChatContextItemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case reference
    case attachment
    case file
    case folder
    case selection
    case note
    case prompt
    case other
}

public struct AiChatContextReference: Codable, Equatable, Sendable {
    public let kind: AiChatContextItemKind
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let metadata: [String: String]

    public init(
        kind: AiChatContextItemKind,
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: [String: String] = [:],
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
    }
}

public struct AiChatContextItem: Codable, Equatable, Sendable {
    public let kind: AiChatContextItemKind
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let metadata: [String: String]
    public let references: [AiChatContextReference]

    public init(
        kind: AiChatContextItemKind,
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: [String: String] = [:],
        references: [AiChatContextReference] = [],
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.references = references
    }
}

public struct AiChatContextAttachment: Codable, Equatable, Sendable {
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let metadata: [String: String]

    public init(
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        metadata: [String: String] = [:],
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.metadata = metadata
    }
}

public struct AiChatCurrentContextSnapshot: Codable, Equatable, Sendable {
    public let summary: String?
    public let references: [AiChatContextReference]
    public let items: [AiChatContextItem]
    public let attachments: [AiChatContextAttachment]

    public init(
        summary: String? = nil,
        references: [AiChatContextReference] = [],
        items: [AiChatContextItem] = [],
        attachments: [AiChatContextAttachment] = [],
    ) {
        self.summary = summary
        self.references = references
        self.items = items
        self.attachments = attachments
    }
}

public enum AiChatRequestContextStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case draftContext = "draft_context"
    case emptyContext = "empty_context"
    case brokenReference = "broken_reference"
    case requestContextLocked = "request_context_locked"
}

public struct AiChatRequestContextBudget: Codable, Equatable, Sendable {
    public static let historyCharacterBudget = 24000
    public static let perAttachmentUTF8ByteBudget = 64 * 1024
    public static let totalAttachmentTextUTF8ByteBudget = 128 * 1024
    public static let `default` = AiChatRequestContextBudget(
        historyCharacters: historyCharacterBudget,
        perAttachmentUTF8Bytes: perAttachmentUTF8ByteBudget,
        totalAttachmentTextUTF8Bytes: totalAttachmentTextUTF8ByteBudget,
    )

    public let historyCharacters: Int
    public let perAttachmentUTF8Bytes: Int
    public let totalAttachmentTextUTF8Bytes: Int

    public init(
        historyCharacters: Int = AiChatRequestContextBudget.historyCharacterBudget,
        perAttachmentUTF8Bytes: Int = AiChatRequestContextBudget.perAttachmentUTF8ByteBudget,
        totalAttachmentTextUTF8Bytes: Int = AiChatRequestContextBudget.totalAttachmentTextUTF8ByteBudget,
    ) {
        self.historyCharacters = historyCharacters
        self.perAttachmentUTF8Bytes = perAttachmentUTF8Bytes
        self.totalAttachmentTextUTF8Bytes = totalAttachmentTextUTF8Bytes
    }
}

public enum AiChatAttachmentSource: String, Codable, Equatable, Sendable, CaseIterable {
    case file
    case folder
    case collectionDocument
    case collectionFile
    case inlineAttachment
    case otherReference
}

public struct AiChatAttachmentSourceLocation: Codable, Equatable, Sendable {
    public let fileURL: URL?
    public let filePath: String?

    public init(fileURL: URL? = nil, filePath: String? = nil) {
        self.fileURL = fileURL
        self.filePath = filePath
    }
}

public enum AiChatAttachmentResolutionFailure: String, Codable, Equatable, Sendable, CaseIterable {
    case tooLarge
    case unsupportedType
    case readFailed
    case permissionDenied
    case brokenReference
    case emptyContent
}

public enum AiChatAttachmentResolutionResult: Codable, Equatable, Sendable {
    case resolvedText(text: String, metadata: [String: String])
    case resolvedReference(metadata: [String: String])
    case resolvedPartial(text: String, truncated: Bool, metadata: [String: String])
    case failure(reason: AiChatAttachmentResolutionFailure, metadata: [String: String])
}

public enum AiChatAttachmentDraftStatus: Codable, Equatable, Sendable {
    case pending
    case resolved(AiChatAttachmentResolutionResult)
}

public struct AiChatAttachmentDraft: Codable, Equatable, Sendable {
    public let id: AiChatAttachmentID
    public let source: AiChatAttachmentSource
    public let displayTitle: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let sourceLocation: AiChatAttachmentSourceLocation
    public let metadata: [String: String]
    public let currentStatus: AiChatAttachmentDraftStatus

    public init(
        id: AiChatAttachmentID,
        source: AiChatAttachmentSource,
        displayTitle: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        sourceLocation: AiChatAttachmentSourceLocation = .init(),
        metadata: [String: String] = [:],
        currentStatus: AiChatAttachmentDraftStatus = .pending,
    ) {
        self.id = id
        self.source = source
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.metadata = metadata
        self.currentStatus = currentStatus
    }
}

public struct AiChatAttachmentSnapshot: Codable, Equatable, Sendable {
    public let id: AiChatAttachmentID
    public let source: AiChatAttachmentSource
    public let displayTitle: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let sourceLocation: AiChatAttachmentSourceLocation
    public let metadata: [String: String]
    public let resolutionResult: AiChatAttachmentResolutionResult

    // swiftlint:disable function_default_parameter_at_end
    public init(
        id: AiChatAttachmentID,
        source: AiChatAttachmentSource,
        displayTitle: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        sourceLocation: AiChatAttachmentSourceLocation = .init(),
        metadata: [String: String] = [:],
        resolutionResult: AiChatAttachmentResolutionResult,
    ) {
        self.id = id
        self.source = source
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.metadata = metadata
        self.resolutionResult = resolutionResult
    }
    // swiftlint:enable function_default_parameter_at_end
}

public struct AiChatRequestContextDraft: Codable, Equatable, Sendable {
    public let currentContext: AiChatCurrentContextSnapshot
    public let addedAttachments: [AiChatAttachmentDraft]
    public let status: AiChatRequestContextStatus

    public init(
        currentContext: AiChatCurrentContextSnapshot = .init(),
        addedAttachments: [AiChatAttachmentDraft] = [],
        status: AiChatRequestContextStatus? = nil,
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.status = status ?? Self.deriveStatus(
            currentContext: currentContext,
            addedAttachments: addedAttachments,
        )
    }

    private static func deriveStatus(
        currentContext: AiChatCurrentContextSnapshot,
        addedAttachments: [AiChatAttachmentDraft],
    ) -> AiChatRequestContextStatus {
        if addedAttachments.contains(where: \.containsBrokenReference) {
            return .brokenReference
        }
        if currentContext.isEmpty, addedAttachments.isEmpty {
            return .emptyContext
        }
        return .draftContext
    }
}

public struct AiChatLockedRequestContextSnapshot: Codable, Equatable, Sendable {
    public let currentContext: AiChatCurrentContextSnapshot
    public let addedAttachments: [AiChatAttachmentSnapshot]
    public let status: AiChatRequestContextStatus

    public init(
        currentContext: AiChatCurrentContextSnapshot = .init(),
        addedAttachments: [AiChatAttachmentSnapshot] = [],
        status: AiChatRequestContextStatus = .requestContextLocked,
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.status = status
    }
}

public enum AiChatSessionStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case restoring
    case active
    case completed
    case failed
    case rebindRequired
}

public enum AiChatSessionRestoreFailure: String, Codable, Sendable, Equatable, CaseIterable {
    case missingRecord
    case contextMismatch
    case corruptedRecord
    case unsupportedVersion
    case unknown
}

public struct AiChatRequestContextSnapshot: Codable, Equatable, Sendable {
    public let sessionID: AiChatSessionID?
    public let requestID: AiChatRequestID
    public let runID: AiChatRunID
    public let provider: AiProvider
    public let model: AiModelHandle
    public let selectedModel: AiProviderModel?
    public let selectedModelRow: AiModelCatalogRow?
    public let selectedThinking: AiThinkingSelection?
    public let sessionStatus: AiChatSessionStatus
    public let currentContext: AiChatCurrentContextSnapshot
    public let requestContext: AiChatLockedRequestContextSnapshot
    public let promptSummary: String?
    public let submittedAtMs: Int64?

    // swiftlint:disable function_default_parameter_at_end
    public init(
        sessionID: AiChatSessionID? = nil,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        provider: AiProvider,
        model: AiModelHandle,
        selectedModel: AiProviderModel? = nil,
        selectedModelRow: AiModelCatalogRow? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        sessionStatus: AiChatSessionStatus,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        requestContext: AiChatLockedRequestContextSnapshot? = nil,
        promptSummary: String? = nil,
        submittedAtMs: Int64? = nil,
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.runID = runID
        self.provider = provider
        self.model = model
        self.selectedModel = selectedModel
        self.selectedModelRow = selectedModelRow
        self.selectedThinking = selectedThinking
        self.sessionStatus = sessionStatus
        let resolvedRequestContext = requestContext ??
            AiChatLockedRequestContextSnapshot(currentContext: currentContext)
        self.requestContext = resolvedRequestContext
        self.currentContext = resolvedRequestContext.currentContext
        self.promptSummary = promptSummary
        self.submittedAtMs = submittedAtMs
    }
    // swiftlint:enable function_default_parameter_at_end
}

public struct AiChatSessionSnapshot: Codable, Equatable, Sendable {
    public let sessionID: AiChatSessionID
    public let status: AiChatSessionStatus
    public let provider: AiProvider
    public let model: AiModelHandle
    public let selectedModelRow: AiModelCatalogRow?
    public let selectedThinking: AiThinkingSelection?
    public let transcriptHistory: [AiChatMessage]
    public let lastRequestID: AiChatRequestID?
    public let lastRunID: AiChatRunID?
    public let lastRequestContext: AiChatLockedRequestContextSnapshot?
    public let updatedAtMs: Int64

    // swiftlint:disable function_default_parameter_at_end
    public init(
        sessionID: AiChatSessionID,
        status: AiChatSessionStatus,
        provider: AiProvider,
        model: AiModelHandle,
        selectedModelRow: AiModelCatalogRow? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        transcriptHistory: [AiChatMessage] = [],
        lastRequestID: AiChatRequestID? = nil,
        lastRunID: AiChatRunID? = nil,
        lastRequestContext: AiChatLockedRequestContextSnapshot? = nil,
        updatedAtMs: Int64,
    ) {
        self.sessionID = sessionID
        self.status = status
        self.provider = provider
        self.model = model
        self.selectedModelRow = selectedModelRow
        self.selectedThinking = selectedThinking
        self.transcriptHistory = transcriptHistory
        self.lastRequestID = lastRequestID
        self.lastRunID = lastRunID
        self.lastRequestContext = lastRequestContext
        self.updatedAtMs = updatedAtMs
    }
    // swiftlint:enable function_default_parameter_at_end
}

public enum AiChatSessionRestoreResult: Codable, Equatable, Sendable {
    case restored(snapshot: AiChatSessionSnapshot)
    case newSession(snapshot: AiChatSessionSnapshot)
    case rebindRequired(snapshot: AiChatSessionSnapshot)
    case failed(reason: AiChatSessionRestoreFailure)
}

private extension AiChatCurrentContextSnapshot {
    var isEmpty: Bool {
        let summaryIsEmpty = summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return summaryIsEmpty && references.isEmpty && items.isEmpty && attachments.isEmpty
    }
}

private extension AiChatAttachmentDraft {
    var containsBrokenReference: Bool {
        guard case let .resolved(result) = currentStatus else {
            return false
        }
        guard case let .failure(reason, _) = result else {
            return false
        }
        return reason == .brokenReference
    }
}

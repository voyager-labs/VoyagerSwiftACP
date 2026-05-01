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

    public init(
        handle: AiModelHandle,
        displayName: String,
        authMethod: ProviderAuthMethod,
        subtitle: String? = nil,
        sortOrder: Int,
        isDefault: Bool = false,
        isRecommended: Bool = false
    ) {
        self.handle = handle
        self.displayName = displayName
        self.authMethod = authMethod
        self.subtitle = subtitle
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isRecommended = isRecommended
    }
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
        metadata: [String: String] = [:]
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
        references: [AiChatContextReference] = []
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
        metadata: [String: String] = [:]
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
        attachments: [AiChatContextAttachment] = []
    ) {
        self.summary = summary
        self.references = references
        self.items = items
        self.attachments = attachments
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
    public let selectedModelRow: AiModelCatalogRow?
    public let sessionStatus: AiChatSessionStatus
    public let currentContext: AiChatCurrentContextSnapshot
    public let promptSummary: String?
    public let submittedAtMs: Int64?

    public init(
        sessionID: AiChatSessionID? = nil,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        provider: AiProvider,
        model: AiModelHandle,
        selectedModelRow: AiModelCatalogRow? = nil,
        sessionStatus: AiChatSessionStatus,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        promptSummary: String? = nil,
        submittedAtMs: Int64? = nil
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.runID = runID
        self.provider = provider
        self.model = model
        self.selectedModelRow = selectedModelRow
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.promptSummary = promptSummary
        self.submittedAtMs = submittedAtMs
    }
}

public struct AiChatSessionSnapshot: Codable, Equatable, Sendable {
    public let sessionID: AiChatSessionID
    public let status: AiChatSessionStatus
    public let provider: AiProvider
    public let model: AiModelHandle
    public let selectedModelRow: AiModelCatalogRow?
    public let transcriptHistory: [AiChatMessage]
    public let lastRequestID: AiChatRequestID?
    public let lastRunID: AiChatRunID?
    public let updatedAtMs: Int64

    public init(
        sessionID: AiChatSessionID,
        status: AiChatSessionStatus,
        provider: AiProvider,
        model: AiModelHandle,
        selectedModelRow: AiModelCatalogRow? = nil,
        transcriptHistory: [AiChatMessage] = [],
        lastRequestID: AiChatRequestID? = nil,
        lastRunID: AiChatRunID? = nil,
        updatedAtMs: Int64
    ) {
        self.sessionID = sessionID
        self.status = status
        self.provider = provider
        self.model = model
        self.selectedModelRow = selectedModelRow
        self.transcriptHistory = transcriptHistory
        self.lastRequestID = lastRequestID
        self.lastRunID = lastRunID
        self.updatedAtMs = updatedAtMs
    }
}

public enum AiChatSessionRestoreResult: Codable, Equatable, Sendable {
    case restored(snapshot: AiChatSessionSnapshot)
    case newSession(snapshot: AiChatSessionSnapshot)
    case rebindRequired(snapshot: AiChatSessionSnapshot)
    case failed(reason: AiChatSessionRestoreFailure)
}

public enum AiChatMessageRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public struct AiChatMessage: Codable, Equatable, Sendable {
    public let role: AiChatMessageRole
    public let content: String

    public init(role: AiChatMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AiChatRequest: Codable, Equatable, Sendable {
    public let context: AiChatRequestContextSnapshot
    public let messages: [AiChatMessage]

    public init(context: AiChatRequestContextSnapshot, messages: [AiChatMessage]) {
        self.context = context
        self.messages = messages
    }
}

public enum AiChatExecutionFailure: String, Codable, Sendable, Equatable, CaseIterable {
    case cancelled
    case transportError
    case unsupportedProvider
    case sessionMismatch
    case unknown
}

public struct AiChatResponse: Codable, Equatable, Sendable {
    public let context: AiChatRequestContextSnapshot
    public let assistantMessage: AiChatMessage
    public let completedAtMs: Int64

    public init(
        context: AiChatRequestContextSnapshot,
        assistantMessage: AiChatMessage,
        completedAtMs: Int64
    ) {
        self.context = context
        self.assistantMessage = assistantMessage
        self.completedAtMs = completedAtMs
    }
}

public enum AiChatEvent: Codable, Equatable, Sendable {
    case started(context: AiChatRequestContextSnapshot)
    case streamChunk(context: AiChatRequestContextSnapshot, delta: String)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

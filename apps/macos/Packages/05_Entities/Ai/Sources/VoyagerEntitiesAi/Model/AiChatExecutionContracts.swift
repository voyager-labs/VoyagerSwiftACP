import Foundation

public enum AiChatMessageRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

public struct AiChatMessage: Codable, Equatable, Sendable {
    public let role: AiChatMessageRole
    public let content: String
    public let createdAtMs: Int64?

    public init(role: AiChatMessageRole, content: String, createdAtMs: Int64? = nil) {
        self.role = role
        self.content = content
        self.createdAtMs = createdAtMs
    }
}

public struct AiChatRequest: Codable, Equatable, Sendable {
    public let context: AiChatRequestContextSnapshot
    public let messages: [AiChatMessage]
    public let responseContract: AiChatProviderResponseContract?

    public init(
        context: AiChatRequestContextSnapshot,
        messages: [AiChatMessage],
        responseContract: AiChatProviderResponseContract? = nil,
    ) {
        self.context = context
        self.messages = messages
        self.responseContract = responseContract
    }
}

public enum AiChatExecutionFailure: String, Codable, Sendable, Equatable, CaseIterable, Error {
    case cancelled
    case authentication
    case modelUnavailable
    case network
    case rateLimited
    case quotaExceeded
    case invalidRequest
    case transportError
    case cliUnavailable
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
        completedAtMs: Int64,
    ) {
        self.context = context
        self.assistantMessage = assistantMessage
        self.completedAtMs = completedAtMs
    }
}

public struct AiChatExecutionActivityID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum AiChatExecutionActivityKind: String, Codable, Equatable, Sendable, CaseIterable {
    case thinking
    case searching
    case toolExecution
    case retrying
    case answerGeneration
}

public enum AiChatExecutionActivityPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case began
    case ended
}

public enum AiChatExecutionEvidenceOrigin: String, Codable, Equatable, Sendable, CaseIterable {
    case providerWire
    case voyagerClient
}

public struct AiChatExecutionActivityEvidence: Codable, Equatable, Sendable {
    public let origin: AiChatExecutionEvidenceOrigin
    public let providerEventType: String
    public let boundaryEventTypes: [String]

    public init(
        origin: AiChatExecutionEvidenceOrigin,
        providerEventType: String,
        boundaryEventTypes: [String] = [],
    ) {
        self.origin = origin
        self.providerEventType = providerEventType
        self.boundaryEventTypes = boundaryEventTypes
    }
}

public struct AiChatExecutionActivitySignal: Codable, Equatable, Sendable {
    public let activityID: AiChatExecutionActivityID
    public let kind: AiChatExecutionActivityKind
    public let phase: AiChatExecutionActivityPhase
    public let evidence: AiChatExecutionActivityEvidence

    public init(
        activityID: AiChatExecutionActivityID,
        kind: AiChatExecutionActivityKind,
        phase: AiChatExecutionActivityPhase,
        evidence: AiChatExecutionActivityEvidence,
    ) {
        self.activityID = activityID
        self.kind = kind
        self.phase = phase
        self.evidence = evidence
    }
}

/// Request execution events must follow this sequence: started once, delta zero or more times,
/// then exactly one terminal final or failed event. Consumers should ignore terminal or late events
/// that no longer match the active request/run context.
public enum AiChatEvent: Codable, Equatable, Sendable {
    case started(context: AiChatRequestContextSnapshot)
    case delta(context: AiChatRequestContextSnapshot, text: String)
    case status(context: AiChatRequestContextSnapshot, signal: AiChatExecutionActivitySignal)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

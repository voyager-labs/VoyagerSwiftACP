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

    public init(role: AiChatMessageRole, content: String) {
        self.role = role
        self.content = content
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

/// Request execution events must follow this sequence: started once, delta zero or more times,
/// then exactly one terminal final or failed event. Consumers should ignore terminal or late events
/// that no longer match the active request/run context.
public enum AiChatEvent: Codable, Equatable, Sendable {
    case started(context: AiChatRequestContextSnapshot)
    case delta(context: AiChatRequestContextSnapshot, text: String)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

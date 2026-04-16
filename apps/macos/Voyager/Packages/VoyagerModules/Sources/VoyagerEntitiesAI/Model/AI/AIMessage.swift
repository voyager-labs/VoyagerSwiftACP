import Foundation

/// A message in an AI chat conversation.
///
/// Voyager-owned neutral type that represents chat messages across
/// OpenAI, Anthropic, and OpenRouter without leaking vendor DTO fields.
///
/// ## Roles
/// - `system`: Sets behavior and context for the model.
/// - `user`: Input from the human user.
/// - `assistant`: Response from the AI model (may include tool calls).
/// - `tool`: Result of a tool/function call.
///
/// ## Codable shape
/// ```
/// { "role": "user", "content": "Hello" }
/// { "role": "assistant", "content": [.text("Hi"), .toolCall(...)] }
/// ```
public struct AIMessage: Sendable, Equatable, Hashable, Identifiable, Codable {
    /// Unique identifier for this message.
    public let id: UUID

    /// The role of the message sender.
    public let role: Role

    /// The message content — either plain text or a list of typed parts.
    public let content: Content

    /// Creates a message.
    public init(id: UUID = UUID(), role: Role, content: Content) {
        self.id = id
        self.role = role
        self.content = content
    }

    // MARK: - Factory Methods

    /// Creates a system message with plain text.
    public static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: .text(text))
    }

    /// Creates a user message with plain text.
    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: .text(text))
    }

    /// Creates an assistant message with plain text.
    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: .text(text))
    }

    /// Creates an assistant message with multi-part content.
    public static func assistant(parts: [AIContentPart]) -> AIMessage {
        AIMessage(role: .assistant, content: .parts(parts))
    }

    /// Creates a tool result message.
    public static func toolResult(_ result: AIToolResult) -> AIMessage {
        AIMessage(role: .tool, content: .parts([.toolResult(result)]))
    }
}

// MARK: - Role

public extension AIMessage {
    /// The role of a message sender in a conversation.
    enum Role: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
        case system
        case user
        case assistant
        case tool
    }
}

// MARK: - Content

public extension AIMessage {
    /// The content of a message — plain text or multi-part.
    enum Content: Sendable, Equatable, Hashable {
        /// Plain text content.
        case text(String)

        /// Multi-part content (text, tool calls, images, etc.).
        case parts([AIContentPart])

        /// Extracts all text from this content.
        public var textValue: String {
            switch self {
            case let .text(s): s
            case let .parts(parts):
                parts.compactMap { part in
                    if case let .text(s) = part { return s }
                    return nil
                }.joined(separator: "\n")
            }
        }

        /// Whether this content contains no text.
        public var isEmpty: Bool { textValue.isEmpty }
    }
}

// MARK: - Content Codable

extension AIMessage.Content: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, parts
    }

    private enum ContentType: String, Codable {
        case text, parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)

        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case .parts:
            let parts = try container.decode([AIContentPart].self, forKey: .parts)
            self = .parts(parts)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .parts(parts):
            try container.encode(ContentType.parts, forKey: .type)
            try container.encode(parts, forKey: .parts)
        }
    }
}

// MARK: - Message Codable

extension AIMessage {
    private enum CodingKeys: String, CodingKey {
        case id, role, content
    }
}

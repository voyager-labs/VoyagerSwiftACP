import Foundation

/// A discriminated content part within a chat message.
///
/// Supports multi-modal messages with text, tool calls, tool results, and images.
/// Designed to represent content from OpenAI, Anthropic, and OpenRouter without
/// leaking vendor-specific DTO fields.
public enum AIContentPart: Sendable, Equatable, Hashable, Codable {
    /// Plain text content.
    case text(String)

    /// A tool call requested by the assistant.
    case toolCall(AIToolCall)

    /// The result of a tool call, provided back to the model.
    case toolResult(AIToolResult)

    /// An image attached to the message.
    case image(AIImageContent)
}

// MARK: - Convenience

public extension AIContentPart {
    /// Extracts the text value if this is a text part, otherwise nil.
    var textValue: String? {
        if case let .text(s) = self { return s }
        return nil
    }
}

// MARK: - AIImageContent

/// Image content embedded in a message.
///
/// Images can be provided as base64-encoded data with a MIME type.
public struct AIImageContent: Sendable, Equatable, Hashable, Codable {
    /// Base64-encoded image data.
    public let base64Data: String

    /// MIME type of the image (e.g. `"image/png"`, `"image/jpeg"`).
    public let mimeType: String

    /// Creates image content.
    public init(base64Data: String, mimeType: String = "image/png") {
        self.base64Data = base64Data
        self.mimeType = mimeType
    }
}

// MARK: - AIContentPart Codable

extension AIContentPart {
    private enum CodingKeys: String, CodingKey {
        case type, text, toolCall, toolResult, image
    }

    private enum PartType: String, Codable {
        case text, toolCall, toolResult, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PartType.self, forKey: .type)

        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case .toolCall:
            let call = try container.decode(AIToolCall.self, forKey: .toolCall)
            self = .toolCall(call)
        case .toolResult:
            let result = try container.decode(AIToolResult.self, forKey: .toolResult)
            self = .toolResult(result)
        case .image:
            let image = try container.decode(AIImageContent.self, forKey: .image)
            self = .image(image)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(PartType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .toolCall(call):
            try container.encode(PartType.toolCall, forKey: .type)
            try container.encode(call, forKey: .toolCall)
        case let .toolResult(result):
            try container.encode(PartType.toolResult, forKey: .type)
            try container.encode(result, forKey: .toolResult)
        case let .image(image):
            try container.encode(PartType.image, forKey: .type)
            try container.encode(image, forKey: .image)
        }
    }
}

// MARK: - AI Tool Result

/// The result of a tool call, provided back to the model.
public struct AIToolResult: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// Matches the ``AIToolCall/id`` this result corresponds to.
    public let id: String

    /// The result content as a string.
    public let content: String

    /// Whether the tool execution was successful.
    public let isSuccess: Bool

    /// Creates a tool result.
    public init(id: String, content: String, isSuccess: Bool = true) {
        self.id = id
        self.content = content
        self.isSuccess = isSuccess
    }
}

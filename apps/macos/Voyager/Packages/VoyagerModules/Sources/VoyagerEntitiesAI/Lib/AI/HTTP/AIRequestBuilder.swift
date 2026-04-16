import Foundation

public struct AIRequestBuilder: Sendable {
    public nonisolated(unsafe) static let shared = AIRequestBuilder()

    public init() {}

    public func buildChatRequest(
        url: String,
        apiKey: String,
        model: String,
        messages: [AIMessage],
        tools: [AIToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
    ) throws -> (url: String, headers: [String: String], body: AIChatRequestBody) {
        let headers = buildAuthHeaders(apiKey: apiKey)
        let body = AIChatRequestBody(
            model: model,
            messages: messages.map(AIChatMessage.from),
            tools: tools.isEmpty ? nil : tools.map(AIChatTool.from),
            temperature: temperature,
            maxTokens: maxTokens,
            stream: stream,
        )
        return (url: url, headers: headers, body: body)
    }

    public func buildAuthHeaders(apiKey: String) -> [String: String] {
        ["Authorization": "Bearer \(apiKey)"]
    }
}

public struct AIChatRequestBody: Encodable, Sendable, Equatable {
    public let model: String
    public let messages: [AIChatMessage]
    public let tools: [AIChatTool]?
    public let temperature: Double?
    public let maxTokens: Int?
    public let stream: Bool

    public init(
        model: String,
        messages: [AIChatMessage],
        tools: [AIChatTool]? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = false,
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, stream
        case maxTokens = "max_tokens"
    }
}

public struct AIChatMessage: Encodable, Sendable, Equatable {
    public let role: String
    public let content: AIChatMessageContent?

    public init(role: String, content: AIChatMessageContent?) {
        self.role = role
        self.content = content
    }

    public static func from(_ message: AIMessage) -> AIChatMessage {
        switch message.content {
        case let .text(text):
            return AIChatMessage(role: message.role.rawValue, content: .text(text))
        case let .parts(parts):
            let chatParts = parts.compactMap { part -> AIChatContentPart? in
                switch part {
                case let .text(text): return .text(text)
                case let .toolCall(call): return .toolCall(call)
                case let .toolResult(result): return .toolResult(result)
                case .image: return nil
                }
            }
            return AIChatMessage(role: message.role.rawValue, content: .parts(chatParts))
        }
    }
}

public enum AIChatMessageContent: Encodable, Equatable, Sendable {
    case text(String)
    case parts([AIChatContentPart])

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case let .parts(parts):
            var container = encoder.unkeyedContainer()
            try container.encode(contentsOf: parts)
        }
    }
}

public enum AIChatContentPart: Encodable, Equatable, Sendable {
    case text(String)
    case toolCall(AIToolCall)
    case toolResult(AIToolResult)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, function, name, arguments, toolCallID, content
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .toolCall(call):
            try container.encode("function", forKey: .type)
            try container.encode(call.id, forKey: .id)
            var funcContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
            try funcContainer.encode(call.name, forKey: .name)
            try funcContainer.encode(call.arguments, forKey: .arguments)
        case let .toolResult(result):
            try container.encode("tool", forKey: .type)
            try container.encode(result.id, forKey: .toolCallID)
            try container.encode(result.content, forKey: .content)
        }
    }
}

public struct AIChatTool: Encodable, Sendable, Equatable {
    public let type: String
    public let function: AIChatToolFunction

    public init(function: AIChatToolFunction) {
        type = "function"
        self.function = function
    }

    public static func from(_ def: AIToolDefinition) -> AIChatTool {
        AIChatTool(function: AIChatToolFunction(
            name: def.name,
            description: def.description,
            parameters: def.parameters,
        ))
    }
}

public struct AIChatToolFunction: Encodable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [String: AnyCodableValue]?

    public init(name: String, description: String, parameters: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct AIToolDefinition: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [String: AnyCodableValue]?

    public init(name: String, description: String, parameters: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct AnyCodableValue: Encodable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        if let string = value as? String {
            try string.encode(to: encoder)
        } else if let int = value as? Int {
            try int.encode(to: encoder)
        } else if let double = value as? Double {
            try double.encode(to: encoder)
        } else if let bool = value as? Bool {
            try bool.encode(to: encoder)
        } else if let array = value as? [Any] {
            try array.map { AnyCodableValue($0) }.encode(to: encoder)
        } else if let dict = value as? [String: Any] {
            try dict.mapValues { AnyCodableValue($0) }.encode(to: encoder)
        } else {
            try String(describing: value).encode(to: encoder)
        }
    }

    public static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

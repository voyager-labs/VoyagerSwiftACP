import Foundation

struct AnthropicMessagesCreateRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessageInput]
    let system: String?
    let thinking: AnthropicThinkingRequest?
    let outputConfig: AnthropicOutputConfig?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        maxTokens = 4096
        system = AnthropicContextPromptBuilder.makeSystemPrompt(from: payload)
        messages = AnthropicMessageInput.makeMessages(from: payload.messages)
        thinking = AnthropicThinkingRequest(payload: payload.thinking)
        outputConfig = AnthropicOutputConfig(payload: payload.thinking)
        stream = true
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case thinking
        case outputConfig = "output_config"
        case stream
    }
}

struct AnthropicMessageInput: Encodable, Sendable {
    let role: String
    let content: String

    static func makeMessages(from messages: [AiChatProviderMessage]) -> [AnthropicMessageInput] {
        messages.compactMap { message in
            switch message.role {
            case .user:
                AnthropicMessageInput(role: "user", content: message.content)
            case .assistant:
                AnthropicMessageInput(role: "assistant", content: message.content)
            case .system, .tool:
                nil
            }
        }
    }
}

struct AnthropicOutputConfig: Encodable, Sendable {
    let effort: String

    init?(payload: AiChatProviderThinkingPayload?) {
        switch payload {
        case let .some(.effort(value)):
            effort = value.rawValue
        case let .some(.adaptive(defaultEffort)):
            guard let defaultEffort else { return nil }
            effort = defaultEffort.rawValue
        case .some(.disabled), .some(.tokenBudget), .some(.none), nil:
            return nil
        }
    }
}

struct AnthropicThinkingRequest: Encodable, Sendable {
    let type: String
    let budgetTokens: Int?
    let display: String?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .disabled:
            type = "disabled"
            budgetTokens = nil
            display = nil
        case let .tokenBudget(value):
            type = "enabled"
            budgetTokens = value
            display = "omitted"
        case .adaptive:
            type = "adaptive"
            budgetTokens = nil
            display = "omitted"
        case .none, .effort:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
        case display
    }
}

struct AnthropicMessageResponse: Decodable, Sendable {
    let content: [AnthropicContentBlock]

    var resolvedText: String? {
        let text = content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

struct AnthropicContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
}

struct AnthropicStreamEvent: Decodable, Sendable {
    let type: String
    let delta: AnthropicStreamDelta?
    let message: AnthropicMessageResponse?
    let contentBlock: AnthropicContentBlock?
    let error: AnthropicStreamError?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case message
        case contentBlock = "content_block"
        case error
    }
}

struct AnthropicStreamError: Decodable, Sendable, Equatable {
    let type: String?
    let message: String?
}

enum AnthropicStreamParsingError: Error, Equatable {
    case invalidPayload
    case provider(AnthropicStreamError?)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .invalidPayload:
            return .invalidRequest
        case let .provider(error):
            switch error?.type {
            case "authentication_error", "permission_error":
                return .authentication
            case "not_found_error":
                return .modelUnavailable
            case "invalid_request_error":
                return .invalidRequest
            case "overloaded_error", "api_error":
                return .network
            case "rate_limit_error":
                return .rateLimited
            default:
                if let message = error?.message?.lowercased(),
                   message.contains("credit") || message.contains("quota") || message.contains("billing")
                   || message.contains("balance") || message.contains("payment") {
                    return .quotaExceeded
                }
                return .invalidRequest
            }
        }
    }
}

struct AnthropicStreamDelta: Decodable, Sendable {
    let type: String?
    let text: String?
}

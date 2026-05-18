import Foundation

struct ParsedOpenAIResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

struct ParsedAnthropicResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

struct OpenAIResponsesCreateRequest: Encodable, Sendable {
    let model: String
    let input: [OpenAIResponsesInputItem]
    let reasoning: OpenAIResponsesReasoning?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        input = Self.makeInput(from: payload)
        reasoning = OpenAIResponsesReasoning(payload: payload.thinking)
        stream = true
    }

    private static func makeInput(from payload: AiChatProviderRequestPayload) -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload),
           !contextText.isEmpty
        {
            items.append(.init(role: .developer, text: contextText))
        }

        items.append(contentsOf: payload.messages.map {
            OpenAIResponsesInputItem(role: .init(messageRole: $0.role), text: $0.content)
        })
        return items
    }
}

struct OpenAIResponsesInputItem: Encodable, Sendable {
    let role: Role
    let content: String

    init(role: Role, text: String) {
        self.role = role
        content = text
    }

    enum Role: String, Encodable, Sendable {
        case developer
        case user
        case assistant

        init(messageRole: AiChatMessageRole) {
            switch messageRole {
            case .system:
                self = .developer
            case .user, .tool:
                self = .user
            case .assistant:
                self = .assistant
            }
        }
    }
}

struct OpenAIResponsesReasoning: Encodable, Sendable {
    let effort: String?
    let budgetTokens: Int?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .none:
            effort = "none"
            budgetTokens = nil
        case let .effort(value):
            effort = value.rawValue
            budgetTokens = nil
        case let .tokenBudget(value):
            effort = nil
            budgetTokens = value
        case let .adaptive(defaultEffort):
            effort = defaultEffort?.rawValue
            budgetTokens = nil
        case .disabled:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

struct OpenAIResponsesFinalResponse: Decodable, Sendable {
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var resolvedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesOutputItem: Decodable, Sendable {
    let content: [OpenAIResponsesOutputContent]?

    var assistantText: String? {
        let text = content?
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesOutputContent: Decodable, Sendable {
    let type: String
    let text: String?
}

struct OpenAIResponsesStreamEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let text: String?
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?
    let response: OpenAIResponsesFinalResponse?
    let error: OpenAIResponsesStreamError?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case text
        case outputText = "output_text"
        case output
        case response
        case error
    }

    var resolvedText: String? {
        if let responseText = response?.resolvedText {
            return responseText
        }

        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesStreamError: Decodable, Sendable {
    let message: String?
    let type: String?
    let code: String?
}

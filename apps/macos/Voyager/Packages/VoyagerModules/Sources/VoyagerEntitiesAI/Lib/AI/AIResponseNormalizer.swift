import Foundation

/// Normalizes AI provider responses into Voyager-owned types.
///
/// Provider adapters use this to convert raw API responses into
/// ``AIGenerationResult`` and ``AIStreamEvent`` values.
public enum AIResponseNormalizer {
    /// Normalizes an OpenAI-style chat completion response.
    public static func normalizeOpenAI(
        data: Data,
        modelID: AIModelID? = nil,
    ) throws -> AIGenerationResult {
        struct OpenAIResponse: Decodable {
            let choices: [OpenAIChoice]
            let usage: OpenAIUsage?
            let model: String?
        }
        struct OpenAIChoice: Decodable {
            let message: OpenAIMessage
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case message, finishReason = "finish_reason"
            }
        }
        struct OpenAIMessage: Decodable {
            let role: String?
            let content: String?
            let toolCalls: [OpenAIToolCall]?
            enum CodingKeys: String, CodingKey {
                case role, content, toolCalls = "tool_calls"
            }
        }
        struct OpenAIToolCall: Decodable {
            let id: String
            let type: String
            let function: OpenAIFunction
            enum CodingKeys: String, CodingKey {
                case id, type, function
            }
        }
        struct OpenAIFunction: Decodable {
            let name: String
            let arguments: String
        }
        struct OpenAIUsage: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let totalTokens: Int
            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }

        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let choice = response.choices.first else {
            throw AINormalizationError.noChoices
        }

        let text = choice.message.content ?? ""
        let finishReason = mapFinishReason(choice.finishReason)
        let usage = AIUsage(
            promptTokens: response.usage?.promptTokens ?? 0,
            completionTokens: response.usage?.completionTokens ?? 0,
        )

        let toolCalls = (choice.message.toolCalls ?? []).map { call in
            AIToolCall(id: call.id, name: call.function.name, arguments: call.function.arguments)
        }

        return AIGenerationResult(
            text: text,
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            modelID: modelID ?? AIModelID(response.model ?? ""),
        )
    }

    /// Parses an SSE line from an OpenAI stream into a stream event.
    public static func parseOpenAISSELine(_ line: String) -> AIStreamEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))

        if json == "[DONE]" { return nil }

        struct SSEDelta: Decodable {
            let choices: [SSEDeltaChoice]
        }
        struct SSEDeltaChoice: Decodable {
            let delta: SSEDeltaContent
            let finishReason: String?
            enum CodingKeys: String, CodingKey {
                case delta, finishReason = "finish_reason"
            }
        }
        struct SSEDeltaContent: Decodable {
            let role: String?
            let content: String?
            let toolCalls: [OpenAIToolCallDelta]?
            enum CodingKeys: String, CodingKey {
                case role, content, toolCalls = "tool_calls"
            }
        }
        struct OpenAIToolCallDelta: Decodable {
            let index: Int?
            let id: String?
            let type: String?
            let function: OpenAIFunctionDelta?
            enum CodingKeys: String, CodingKey {
                case index, id, type, function
            }
        }
        struct OpenAIFunctionDelta: Decodable {
            let name: String?
            let arguments: String?
        }

        guard let data = json.data(using: .utf8),
              let delta = try? JSONDecoder().decode(SSEDelta.self, from: data),
              let choice = delta.choices.first
        else {
            return nil
        }

        if let content = choice.delta.content, !content.isEmpty {
            return .textDelta(content)
        }

        if let firstCall = choice.delta.toolCalls?.first {
            let id = firstCall.id ?? ""
            let name = firstCall.function?.name
            let args = firstCall.function?.arguments ?? ""
            if !args.isEmpty {
                return .toolCallDelta(id: id, name: name, argumentsDelta: args)
            }
        }

        return nil
    }

    /// Maps OpenAI/Anthropic finish reason strings to Voyager enum.
    public static func mapFinishReason(_ reason: String?) -> AIFinishReason {
        switch reason {
        case "stop": .stop
        case "tool_calls": .toolCall
        case "length": .length
        case "content_filter": .contentFilter
        default: reason == nil ? .stop : .other
        }
    }
}

public enum AINormalizationError: Error, Sendable {
    case noChoices
    case decodingFailed
    case unexpectedFormat
}

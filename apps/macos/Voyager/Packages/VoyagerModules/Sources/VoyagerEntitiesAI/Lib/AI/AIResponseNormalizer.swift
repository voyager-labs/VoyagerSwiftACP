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

    // MARK: - Anthropic Normalization

    /// Normalizes an Anthropic Messages API response into a Voyager-owned result.
    ///
    /// Parses Anthropic's content blocks (text + tool_use) and stop_reason into
    /// ``AIGenerationResult`` with normalized finish reasons and tool calls.
    public static func normalizeAnthropic(
        data: Data,
        modelID: AIModelID? = nil,
    ) throws -> AIGenerationResult {
        struct AnthropicResponse: Decodable {
            let content: [AnthropicContentBlock]
            let stopReason: String?
            let usage: AnthropicUsage?
            let model: String?
            enum CodingKeys: String, CodingKey {
                case content, stopReason = "stop_reason", usage, model
            }
        }
        struct AnthropicContentBlock: Decodable {
            let type: String
            let text: String?
            let id: String?
            let name: String?
            let input: String?
        }
        struct AnthropicUsage: Decodable {
            let inputTokens: Int
            let outputTokens: Int
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        let textParts = response.content.compactMap(\.text)
        let text = textParts.joined(separator: "")

        let toolCalls = response.content.compactMap { block -> AIToolCall? in
            guard block.type == "tool_use", let id = block.id, let name = block.name else { return nil }
            return AIToolCall(id: id, name: name, arguments: block.input ?? "{}")
        }

        let finishReason = mapAnthropicFinishReason(response.stopReason)
        let usage = AIUsage(
            promptTokens: response.usage?.inputTokens ?? 0,
            completionTokens: response.usage?.outputTokens ?? 0,
        )

        return AIGenerationResult(
            text: text,
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            modelID: modelID ?? AIModelID(response.model ?? ""),
        )
    }

    /// Parses an Anthropic SSE line into a Voyager stream event.
    ///
    /// Handles the Anthropic-specific SSE event types:
    /// `content_block_delta` (text + tool input), `message_delta` (finish).
    public static func parseAnthropicSSELine(_ line: String) -> AIStreamEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let json = String(line.dropFirst(6))
        if json == "[DONE]" { return nil }

        guard let data = json.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = jsonObj["type"] as? String
        else { return nil }

        switch type {
        case "content_block_delta":
            guard let delta = jsonObj["delta"] as? [String: Any] else { return nil }
            let deltaType = delta["type"] as? String

            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                return .textDelta(text)
            }

            if deltaType == "input_json_delta", let partialJson = delta["partial_json"] as? String,
               !partialJson.isEmpty
            {
                let index = jsonObj["index"] as? Int ?? 0
                return .toolCallDelta(id: "tool_\(index)", name: nil, argumentsDelta: partialJson)
            }

            return nil

        case "message_delta":
            guard let deltaDict = jsonObj["delta"] as? [String: Any] else { return nil }
            let stopReason = deltaDict["stop_reason"] as? String
            let usageDict = jsonObj["usage"] as? [String: Any]
            let inputTokens = usageDict?["input_tokens"] as? Int ?? 0
            let outputTokens = usageDict?["output_tokens"] as? Int ?? 0
            let finishReason = mapAnthropicFinishReason(stopReason)
            return .finish(finishReason, AIUsage(promptTokens: inputTokens, completionTokens: outputTokens))

        case "content_block_start":
            guard let contentBlock = jsonObj["content_block"] as? [String: Any],
                  contentBlock["type"] as? String == "tool_use",
                  let id = contentBlock["id"] as? String,
                  let name = contentBlock["name"] as? String
            else { return nil }
            return .toolCallDelta(id: id, name: name, argumentsDelta: "")

        default:
            return nil
        }
    }

    /// Maps Anthropic stop reasons to Voyager finish reasons.
    public static func mapAnthropicFinishReason(_ reason: String?) -> AIFinishReason {
        switch reason {
        case "end_turn": .stop
        case "tool_use": .toolCall
        case "max_tokens": .length
        case "stop_sequence": .stop
        case "refusal": .contentFilter
        default: reason == nil ? .stop : .other
        }
    }
}

public enum AINormalizationError: Error, Sendable {
    case noChoices
    case decodingFailed
    case unexpectedFormat
}

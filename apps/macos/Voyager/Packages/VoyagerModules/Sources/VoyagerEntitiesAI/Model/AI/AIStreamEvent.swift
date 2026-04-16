import Foundation

/// A single event in an AI streaming response.
///
/// Provider-agnostic stream event type that can represent deltas from
/// OpenAI, Anthropic, and OpenRouter without leaking vendor-specific fields.
///
/// ## Event lifecycle (typical)
/// 1. One or more ``textDelta`` events delivering text incrementally.
/// 2. Zero or more ``toolCallDelta`` events if the model invokes tools.
/// 3. A single ``finish`` event with usage and finish reason.
/// 4. Optionally an ``error`` event if something went wrong.
public enum AIStreamEvent: Sendable, Equatable {
    /// A chunk of generated text.
    case textDelta(String)

    /// A tool call being streamed (arguments arrive incrementally).
    /// Multiple deltas with the same `id` should be accumulated.
    case toolCallDelta(id: String, name: String?, argumentsDelta: String)

    /// A complete tool call (sent when the tool arguments are fully received).
    case toolCallComplete(AIToolCall)

    /// Stream finished. Contains the final finish reason and usage.
    case finish(AIFinishReason, AIUsage)

    /// Response metadata received (model ID, response ID).
    case responseMetadata(responseID: String?, modelID: AIModelID?)

    /// An error occurred during streaming.
    case error(String)

    /// A warning from the provider (non-fatal).
    case warning(String)
}

// MARK: - Codable

extension AIStreamEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case delta
        case id
        case name
        case argumentsDelta
        case toolCall
        case finishReason
        case usage
        case responseID
        case modelID
        case message
    }

    private enum EventType: String, Codable {
        case textDelta
        case toolCallDelta
        case toolCallComplete
        case finish
        case responseMetadata
        case error
        case warning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .textDelta:
            let delta = try container.decode(String.self, forKey: .delta)
            self = .textDelta(delta)

        case .toolCallDelta:
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            let argumentsDelta = try container.decode(String.self, forKey: .argumentsDelta)
            self = .toolCallDelta(id: id, name: name, argumentsDelta: argumentsDelta)

        case .toolCallComplete:
            let toolCall = try container.decode(AIToolCall.self, forKey: .toolCall)
            self = .toolCallComplete(toolCall)

        case .finish:
            let finishReason = try container.decode(AIFinishReason.self, forKey: .finishReason)
            let usage = try container.decode(AIUsage.self, forKey: .usage)
            self = .finish(finishReason, usage)

        case .responseMetadata:
            let responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
            let modelID = try container.decodeIfPresent(AIModelID.self, forKey: .modelID)
            self = .responseMetadata(responseID: responseID, modelID: modelID)

        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message)

        case .warning:
            let message = try container.decode(String.self, forKey: .message)
            self = .warning(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .textDelta(delta):
            try container.encode(EventType.textDelta, forKey: .type)
            try container.encode(delta, forKey: .delta)

        case let .toolCallDelta(id, name, argumentsDelta):
            try container.encode(EventType.toolCallDelta, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(argumentsDelta, forKey: .argumentsDelta)

        case let .toolCallComplete(toolCall):
            try container.encode(EventType.toolCallComplete, forKey: .type)
            try container.encode(toolCall, forKey: .toolCall)

        case let .finish(finishReason, usage):
            try container.encode(EventType.finish, forKey: .type)
            try container.encode(finishReason, forKey: .finishReason)
            try container.encode(usage, forKey: .usage)

        case let .responseMetadata(responseID, modelID):
            try container.encode(EventType.responseMetadata, forKey: .type)
            try container.encodeIfPresent(responseID, forKey: .responseID)
            try container.encodeIfPresent(modelID, forKey: .modelID)

        case let .error(message):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(message, forKey: .message)

        case let .warning(message):
            try container.encode(EventType.warning, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

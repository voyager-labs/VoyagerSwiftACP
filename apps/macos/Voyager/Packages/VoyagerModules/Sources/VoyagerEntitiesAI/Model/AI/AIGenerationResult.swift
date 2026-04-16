import Foundation

/// The result of a complete (non-streaming) AI generation.
///
/// Contains the generated text, finish reason, usage statistics, and any
/// tool calls the model requested.
public struct AIGenerationResult: Sendable, Equatable {
    /// The generated text content.
    public let text: String

    /// Why generation stopped.
    public let finishReason: AIFinishReason

    /// Token usage statistics.
    public let usage: AIUsage

    /// Tool calls requested by the model (empty if none).
    public let toolCalls: [AIToolCall]

    /// The model ID that was used for this generation.
    public let modelID: AIModelID?

    /// Creates a generation result.
    public init(
        text: String,
        finishReason: AIFinishReason,
        usage: AIUsage = .zero,
        toolCalls: [AIToolCall] = [],
        modelID: AIModelID? = nil,
    ) {
        self.text = text
        self.finishReason = finishReason
        self.usage = usage
        self.toolCalls = toolCalls
        self.modelID = modelID
    }

    /// Whether the model requested tool calls.
    public var hasToolCalls: Bool { !toolCalls.isEmpty }
}

// MARK: - Factory

public extension AIGenerationResult {
    /// Creates a simple text result with stop reason.
    static func text(_ content: String) -> AIGenerationResult {
        AIGenerationResult(text: content, finishReason: .stop)
    }
}

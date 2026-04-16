import Foundation

/// Normalized reason why an AI generation finished.
///
/// Provides a unified finish reason across OpenAI, Anthropic, and OpenRouter.
/// The raw provider-specific value is preserved for debugging and edge-case handling.
///
/// ## Mapping from providers
/// - OpenAI `stop` → ``stop``
/// - OpenAI `tool_calls` → ``toolCall``
/// - OpenAI `length` → ``length``
/// - OpenAI `content_filter` → ``contentFilter``
/// - Anthropic `end_turn` → ``stop``
/// - Anthropic `tool_use` → ``toolCall``
/// - Anthropic `max_tokens` → ``length``
public enum AIFinishReason: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    /// Model completed generation naturally (EOS / end_turn / stop).
    case stop

    /// Model stopped to invoke one or more tools.
    case toolCall

    /// Model hit the maximum token limit.
    case length

    /// Content was filtered by safety systems before generation could complete.
    case contentFilter

    /// Generation was cancelled by the client.
    case cancelled

    /// Generation stopped due to an error.
    case error

    /// Generation stopped for a provider-specific reason not covered above.
    case other
}

// MARK: - Convenience

public extension AIFinishReason {
    /// Whether this finish reason indicates the model wants to invoke tools.
    var isToolCallRequest: Bool { self == .toolCall }

    /// Whether generation completed successfully (not error/cancelled).
    var isSuccessful: Bool {
        switch self {
        case .stop, .toolCall, .length, .contentFilter: true
        case .cancelled, .error, .other: false
        }
    }
}

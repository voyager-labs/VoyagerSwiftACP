import Foundation

/// Strongly-typed identifier for an AI provider at the runtime/adapter layer.
///
/// Distinct from ``AIProvider`` (which is a connection-management enum with exactly three locked v1 cases).
/// ``AIProviderID`` is the runtime identity used by inference adapters and capability resolution.
///
/// ## Relationship to Foundation types
/// - ``AIProvider``: connection-level enum (`chatgptCodex`, `openai`, `anthropic`) — frozen.
/// - ``AIProviderID``: runtime-level identifier — extensible as new providers are added.
///
/// The mapping from ``AIProvider`` to ``AIProviderID`` is owned by the adapter layer.
public struct AIProviderID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    /// The raw string value of the provider identifier.
    public let rawValue: String

    /// Creates a provider ID from a raw string value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a provider ID from an arbitrary string.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Well-known provider IDs

public extension AIProviderID {
    /// OpenAI (direct API).
    static let openai = AIProviderID(rawValue: "openai")

    /// Anthropic (direct API).
    static let anthropic = AIProviderID(rawValue: "anthropic")

    /// OpenRouter (OpenAI-compatible aggregator).
    static let openRouter = AIProviderID(rawValue: "openRouter")

    /// ChatGPT Codex (OAuth-based).
    static let chatgptCodex = AIProviderID(rawValue: "chatgptCodex")
}

// MARK: - CustomStringConvertible

extension AIProviderID: CustomStringConvertible {
    public var description: String { rawValue }
}

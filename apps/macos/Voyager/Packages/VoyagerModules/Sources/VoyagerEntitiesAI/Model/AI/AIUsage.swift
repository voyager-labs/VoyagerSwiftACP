import Foundation

/// Token usage statistics for an AI generation request.
///
/// Tracks token consumption for cost estimation, rate-limit awareness,
/// and context-window management across all supported providers.
public struct AIUsage: Sendable, Equatable, Hashable, Codable {
    /// Number of tokens in the input prompt.
    public let promptTokens: Int

    /// Number of tokens in the generated completion.
    public let completionTokens: Int

    /// Total tokens consumed (prompt + completion).
    public var totalTokens: Int { promptTokens + completionTokens }

    /// Creates usage statistics.
    ///
    /// - Parameters:
    ///   - promptTokens: Tokens in the input prompt.
    ///   - completionTokens: Tokens in the generated completion.
    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - Zero

public extension AIUsage {
    /// A zero-usage sentinel for requests that have not yet completed or where
    /// usage information is unavailable.
    static let zero = AIUsage(promptTokens: 0, completionTokens: 0)
}

import Foundation

/// Capability flags describing what an AI provider supports.
///
/// Used at the adapter layer to negotiate features (streaming, tool calling, etc.)
/// without leaking provider-specific capability enums.
///
/// ## Usage
/// ```swift
/// let caps: AIProviderCapability = [.streaming, .toolCalling]
/// if caps.contains(.streaming) { ... }
/// ```
public struct AIProviderCapability: OptionSet, Sendable, Equatable, Hashable, Codable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    // MARK: - Capability flags

    /// Provider supports text generation (all providers support this).
    public static let textGeneration = AIProviderCapability(rawValue: 1 << 0)

    /// Provider supports streaming responses.
    public static let streaming = AIProviderCapability(rawValue: 1 << 1)

    /// Provider supports tool/function calling.
    public static let toolCalling = AIProviderCapability(rawValue: 1 << 2)

    /// Provider supports structured/JSON output.
    public static let structuredOutput = AIProviderCapability(rawValue: 1 << 3)

    /// Provider supports multi-modal input (images in messages).
    public static let multimodalInput = AIProviderCapability(rawValue: 1 << 4)

    /// Provider supports reasoning/thinking mode.
    public static let reasoning = AIProviderCapability(rawValue: 1 << 5)

    /// Provider supports multiple tool calls in a single response.
    public static let parallelToolCalls = AIProviderCapability(rawValue: 1 << 6)

    /// Provider reports token usage statistics.
    public static let usageReporting = AIProviderCapability(rawValue: 1 << 7)
}

// MARK: - Well-known combinations

public extension AIProviderCapability {
    /// Capabilities common to all supported providers.
    static let base: AIProviderCapability = [.textGeneration, .usageReporting]

    /// Full capability set.
    static let all: AIProviderCapability = [
        .textGeneration, .streaming, .toolCalling, .structuredOutput,
        .multimodalInput, .reasoning, .parallelToolCalls, .usageReporting,
    ]
}

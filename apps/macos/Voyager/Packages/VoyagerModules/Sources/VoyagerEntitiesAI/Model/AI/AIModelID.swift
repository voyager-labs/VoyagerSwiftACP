import Foundation

/// Strongly-typed identifier for a specific AI model within a provider.
///
/// Model IDs are provider-specific strings (e.g. `"gpt-4o"`, `"claude-sonnet-4-20250514"`,
/// `"openrouter/auto"`). This type wraps the raw string for type safety in signatures
/// without constraining the value space.
public struct AIModelID: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    /// The raw string value of the model identifier.
    public let rawValue: String

    /// Creates a model ID from a raw string value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a model ID from an arbitrary string.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - CustomStringConvertible

extension AIModelID: CustomStringConvertible {
    public var description: String { rawValue }
}

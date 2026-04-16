import Foundation

/// A tool/function call requested by the AI model during generation.
///
/// Represents the model's intent to invoke a tool. The caller is responsible for
/// executing the tool and providing the result back to the model.
///
/// This type is provider-agnostic — OpenAI `function_call`/`tool_calls` and
/// Anthropic `tool_use` blocks both map here.
public struct AIToolCall: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// Unique identifier for this tool call within the generation.
    public let id: String

    /// The name of the tool to invoke.
    public let name: String

    /// The arguments to pass to the tool, as a JSON-encoded string.
    public let arguments: String

    /// Creates a tool call.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this tool call.
    ///   - name: The tool name.
    ///   - arguments: JSON-encoded arguments string.
    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - CustomStringConvertible

extension AIToolCall: CustomStringConvertible {
    public var description: String { "AIToolCall(\(id), \(name))" }
}

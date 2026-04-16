// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/OpenAI/OpenAIConfiguration.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Configuration for the direct OpenAI API adapter.
///
/// Targets the official OpenAI chat completions endpoint at `api.openai.com`.
/// Supports API key authentication and optional organization header.
///
/// ## Usage
/// ```swift
/// let config = OpenAIConfiguration(
///     apiKey: "sk-...",
///     model: AIModelID("gpt-4o")
/// )
/// let adapter = OpenAIAdapter(configuration: config)
/// let result = try await adapter.generate(messages: [.user("Hello")])
/// ```
public struct OpenAIConfiguration: Sendable, Equatable {
    /// API key for Bearer token authentication.
    public let apiKey: String

    /// The default model to use when none is specified in a call.
    public let defaultModel: AIModelID

    /// Optional OpenAI organization ID (sent as `OpenAI-Organization` header).
    public let organizationID: String?

    /// The full URL for the chat completions endpoint.
    public let chatCompletionsURL: String

    /// Creates a configuration for the direct OpenAI API.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key (starts with `sk-`).
    ///   - defaultModel: Default model ID (e.g. `AIModelID("gpt-4o")`).
    ///   - organizationID: Optional OpenAI organization ID.
    ///   - baseURL: Override base URL (defaults to `https://api.openai.com/v1`).
    public init(
        apiKey: String,
        defaultModel: AIModelID = AIModelID("gpt-4o"),
        organizationID: String? = nil,
        baseURL: String = "https://api.openai.com/v1",
    ) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.organizationID = organizationID
        let stripped = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        chatCompletionsURL = stripped + "/chat/completions"
    }

    /// Combined authorization + organization headers.
    public var requestHeaders: [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
        ]
        if let org = organizationID {
            headers["OpenAI-Organization"] = org
        }
        return headers
    }
}

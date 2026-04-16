// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/Anthropic/AnthropicConfiguration.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Configuration for the direct Anthropic Messages API adapter.
///
/// Targets the official Anthropic Messages endpoint at `api.anthropic.com`.
/// Uses `x-api-key` header authentication (not Bearer token).
///
/// ## Usage
/// ```swift
/// let config = AnthropicConfiguration(
///     apiKey: "sk-ant-...",
///     model: AIModelID("claude-sonnet-4-20250514")
/// )
/// let adapter = AnthropicAdapter(configuration: config)
/// let result = try await adapter.generate(messages: [.user("Hello")])
/// ```
public struct AnthropicConfiguration: Sendable, Equatable {
    public static let defaultBaseURL = "https://api.anthropic.com"
    public static let defaultAPIVersion = "2023-06-01"

    public let apiKey: String
    public let defaultModel: AIModelID
    public let baseURL: String
    public let apiVersion: String
    public let messagesURL: String

    public init(
        apiKey: String,
        defaultModel: AIModelID = AIModelID("claude-sonnet-4-20250514"),
        baseURL: String = AnthropicConfiguration.defaultBaseURL,
        apiVersion: String = AnthropicConfiguration.defaultAPIVersion,
    ) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        let stripped = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.baseURL = stripped
        self.apiVersion = apiVersion
        messagesURL = stripped + "/v1/messages"
    }

    public var requestHeaders: [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": apiVersion,
            "content-type": "application/json",
        ]
    }
}

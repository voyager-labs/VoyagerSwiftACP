// Portions adapted from Swift AI SDK (Apache-2.0).
// Original: Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift
// Commit: 88225c3fa3544e30fe361ca4aa03c4a60c7444ec

import Foundation

/// Configuration for an OpenAI-compatible provider adapter.
///
/// Encapsulates base URL, authentication, custom headers, and capability flags
/// for providers that implement the OpenAI chat completions API surface
/// (e.g. OpenRouter, Together AI, Groq, local inference servers).
///
/// ## Usage
/// ```swift
/// let config = OpenAICompatibleConfiguration(
///     providerID: .openRouter,
///     baseURL: "https://openrouter.ai/api/v1",
///     apiKey: "sk-or-...",
///     model: AIModelID("openrouter/auto")
/// )
/// let adapter = OpenAICompatibleAdapter(configuration: config)
/// let result = try await adapter.generate(messages: [.user("Hello")])
/// ```
public struct OpenAICompatibleConfiguration: Sendable, Equatable {
    /// The Voyager provider identifier for this adapter.
    public let providerID: AIProviderID

    /// The base URL for the chat completions endpoint.
    ///
    /// Must include the full path up to (but not including) `/chat/completions`.
    /// Trailing slashes are stripped automatically.
    ///
    /// Examples:
    /// - `"https://openrouter.ai/api/v1"`
    /// - `"https://api.groq.com/openai/v1"`
    /// - `"http://localhost:11434/v1"`
    public let baseURL: String

    /// API key for authentication. Appended as a Bearer token.
    ///
    /// Set to `nil` for unauthenticated local endpoints.
    public let apiKey: String?

    /// Additional HTTP headers injected into every request.
    ///
    /// Useful for provider-specific headers like `HTTP-Referer` or `X-Title`.
    public let extraHeaders: [String: String]

    /// The default model to use when none is specified in a call.
    public let defaultModel: AIModelID

    /// Optional query parameters appended to every request URL.
    public let queryParams: [String: String]

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - providerID: Voyager provider identifier.
    ///   - baseURL: Base URL (trailing slash stripped).
    ///   - apiKey: Optional API key for Bearer auth.
    ///   - extraHeaders: Additional HTTP headers.
    ///   - defaultModel: Default model ID.
    ///   - queryParams: Query parameters appended to requests.
    public init(
        providerID: AIProviderID,
        baseURL: String,
        apiKey: String? = nil,
        extraHeaders: [String: String] = [:],
        defaultModel: AIModelID,
        queryParams: [String: String] = [:],
    ) {
        self.providerID = providerID
        self.baseURL = Self.stripTrailingSlash(baseURL)
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.defaultModel = defaultModel
        self.queryParams = queryParams
    }

    /// The full URL for the chat completions endpoint.
    public var chatCompletionsURL: String {
        var url = baseURL + "/chat/completions"
        if !queryParams.isEmpty {
            var components = URLComponents(string: url) ?? URLComponents()
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let urlString = components.string {
                url = urlString
            }
        }
        return url
    }

    /// Combined authorization + extra headers.
    public var requestHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        for (key, value) in extraHeaders {
            headers[key] = value
        }
        return headers
    }

    private static func stripTrailingSlash(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

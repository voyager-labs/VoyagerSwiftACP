import Foundation

/// Well-known test credential strings.
/// These are NOT real secrets — they are safe sentinel values used only in tests.
enum FixtureCredentials {
    // MARK: - Tokens

    static let refreshToken = "voyager-test-refresh-token-fixture"
    static let accessToken = "voyager-test-access-token-fixture"

    // MARK: - API Keys

    static let openAIApiKey = "sk-test-openai-fixture-key-000000000000"
    static let anthropicApiKey = "sk-ant-test-anthropic-fixture-key-000000"

    // MARK: - JSON payloads

    /// A complete auth.json fixture with OAuth-style tokens.
    static var authJSON: Data {
        """
        {
          "provider": "chatgpt-codex",
          "refreshToken": "\(refreshToken)",
          "accessToken": "\(accessToken)"
        }
        """.data(using: .utf8)!
    }

    /// An API-key style credential fixture.
    static var apiKeyJSON: Data {
        """
        {
          "provider": "openai",
          "apiKey": "\(openAIApiKey)"
        }
        """.data(using: .utf8)!
    }

    // MARK: - Sentinel collection (for redaction checks)

    /// All secret-bearing strings that must never appear in logs.
    static let allSecrets: [String] = [
        refreshToken,
        accessToken,
        openAIApiKey,
        anthropicApiKey,
    ]
}

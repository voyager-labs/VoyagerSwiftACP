import Foundation

/// OAuth configuration for the Codex (OpenAI) browser-based authentication flow.
///
/// Defaults are tuned for the production OpenAI auth endpoint. Override any
/// value via environment variables for testing or staging environments.
public struct CodexOAuthConfig: Sendable, Equatable {
    public let clientId: String
    public let issuer: URL
    public let authorizePath: String
    public let tokenPath: String
    public let redirectPort: Int
    public let redirectPath: String
    public let scopes: [String]
    public let originator: String

    /// Production defaults. Reads overrides from environment variables when set.
    public static let `default` = CodexOAuthConfig(
        clientId: ProcessInfo.processInfo.environment["OPENAI_CODEX_OAUTH_CLIENT_ID"]
            ?? "app_EMoamEEZ73f0CkXaXp7hrann",
        issuer: URL(string: "https://auth.openai.com")!,
        authorizePath: "/oauth/authorize",
        tokenPath: "/oauth/token",
        redirectPort: ProcessInfo.processInfo.environment["OPENAI_CODEX_OAUTH_REDIRECT_PORT"]
            .flatMap { Int($0) } ?? 1455,
        redirectPath: "/auth/callback",
        scopes: [
            "openid",
            "profile",
            "email",
            "offline_access",
            "api.connectors.read",
            "api.connectors.invoke",
        ],
        originator: "codex_cli_rs"
    )

    public var redirectURI: String {
        "http://localhost:\(redirectPort)\(redirectPath)"
    }

    public var authorizeEndpoint: URL {
        issuer.appendingPathComponent(authorizePath)
    }

    public var tokenEndpoint: URL {
        issuer.appendingPathComponent(tokenPath)
    }

    /// Build the full authorize URL with PKCE parameters.
    public func authorizeURL(pkceChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkceChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components.url!
    }
}

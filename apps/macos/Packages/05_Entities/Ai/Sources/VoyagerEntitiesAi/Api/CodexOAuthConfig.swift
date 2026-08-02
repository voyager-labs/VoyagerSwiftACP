import Foundation

/// OAuth configuration for the Codex (OpenAI) browser-based authentication flow.
public struct CodexOAuthConfig: Sendable, Equatable {
    private static let defaultClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let defaultRedirectPort = 1455

    public let clientId: String
    public let issuer: URL
    public let authorizePath: String
    public let tokenPath: String
    public let redirectPort: Int
    public let redirectPath: String
    public let scopes: [String]
    public let originator: String

    public static let `default` = CodexOAuthConfig(
        clientId: defaultClientID,
        issuer: {
            guard let url = URL(string: "https://auth.openai.com") else {
                fatalError("Invalid hardcoded issuer URL")
            }
            return url
        }(),
        authorizePath: "/oauth/authorize",
        tokenPath: "/oauth/token",
        redirectPort: defaultRedirectPort,
        redirectPath: "/auth/callback",
        scopes: [
            "openid",
            "profile",
            "email",
            "offline_access",
            "api.connectors.read",
            "api.connectors.invoke",
        ],
        originator: "codex_cli_rs",
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
        guard var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false) else {
            return authorizeEndpoint
        }
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
        return components.url ?? authorizeEndpoint
    }
}

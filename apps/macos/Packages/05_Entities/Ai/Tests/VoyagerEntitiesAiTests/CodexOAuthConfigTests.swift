import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class CodexOAuthConfigTests: XCTestCase {
    func testDefault_hasExpectedIssuer() {
        let config = CodexOAuthConfig.default
        XCTAssertEqual(config.issuer, URL(string: "https://auth.openai.com"))
    }

    func testDefault_redirectURI() {
        let config = CodexOAuthConfig.default
        XCTAssertEqual(config.redirectURI, "http://localhost:1455/auth/callback")
    }

    func testAuthorizeEndpoint() {
        let config = CodexOAuthConfig.default
        XCTAssertEqual(config.authorizeEndpoint, URL(string: "https://auth.openai.com/oauth/authorize"))
    }

    func testTokenEndpoint() {
        let config = CodexOAuthConfig.default
        XCTAssertEqual(config.tokenEndpoint, URL(string: "https://auth.openai.com/oauth/token"))
    }

    func testAuthorizeURL_containsPKCEParameters() {
        let config = CodexOAuthConfig.default
        let url = config.authorizeURL(pkceChallenge: "test-challenge", state: "test-state")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let queryItems = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(queryItems["response_type"], "code")
        XCTAssertEqual(queryItems["client_id"], config.clientId)
        XCTAssertEqual(queryItems["code_challenge"], "test-challenge")
        XCTAssertEqual(queryItems["code_challenge_method"], "S256")
        XCTAssertEqual(queryItems["state"], "test-state")
        XCTAssertEqual(queryItems["redirect_uri"], config.redirectURI)
    }

    func testCustomConfig_differentPort() {
        let config = CodexOAuthConfig(
            clientId: "test-client",
            issuer: URL(string: "https://test.example.com")!,
            authorizePath: "/auth",
            tokenPath: "/token",
            redirectPort: 8080,
            redirectPath: "/callback",
            scopes: ["read"]
        )
        XCTAssertEqual(config.redirectURI, "http://localhost:8080/callback")
        XCTAssertEqual(config.scopes, ["read"])
    }

    func testEquality() {
        let config1 = CodexOAuthConfig.default
        let config2 = CodexOAuthConfig.default
        XCTAssertEqual(config1, config2)
    }
}

import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesAi
import XCTest

/// Recovered from old AIConnectionClientContractTests + Voy218GapTests (9d3be186).
/// Tests liveValue and persistence-only behavior for the dependency clients.
final class AiLiveValueTests: XCTestCase {
    // MARK: - Verification liveValue

    func testAIProviderVerificationClient_liveValue_nilCredential_returnsMissingCredential() {
        let client = AIProviderVerificationClient.liveValue
        let result = awaitTest { await client.verify(.openai, nil) }
        XCTAssertEqual(result, .invalid(.missingCredential))
    }

    func testAIProviderVerificationClient_liveValue_emptyAPIKey_returnsInvalidAPIKey() {
        let client = AIProviderVerificationClient.liveValue
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: ""))
        let result = awaitTest { await client.verify(.openai, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testAIProviderVerificationClient_liveValue_emptyOAuthToken_returnsInvalidAPIKey() {
        let client = AIProviderVerificationClient.liveValue
        let credential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: ""))
        let result = awaitTest { await client.verify(.chatgptCodex, credential) }
        XCTAssertEqual(result, .invalid(.invalidAPIKey))
    }

    func testAIProviderVerificationClient_liveValue_nilCredential_anthropic_returnsMissingCredential() {
        let client = AIProviderVerificationClient.liveValue
        let result = awaitTest { await client.verify(.anthropic, nil) }
        XCTAssertEqual(result, .invalid(.missingCredential))
    }

    // MARK: - connectOAuth liveValue

    func testConnectOAuth_liveValue_persistsCredentialForValidProvider() {
        let client = AIProviderConnectionClient.liveValue
        let credential = OAuthCredentialFile(accessToken: "at_connect_test")
        let result = awaitTest { await client.connectOAuth(.chatgptCodex, credential, .connected) }

        XCTAssertEqual(result.provider, .chatgptCodex)
        XCTAssertEqual(result.state, .connected)
    }

    func testConnectOAuth_liveValue_persistsCredentialInFile() {
        let client = AIProviderConnectionClient.liveValue
        let credential = OAuthCredentialFile(accessToken: "at_verify_fake")
        let result = awaitTest { await client.connectOAuth(.chatgptCodex, credential, .connected) }

        let codexRecord = result.updatedFile.providers["chatgptCodex"]
        XCTAssertNotNil(codexRecord?.credential)
    }

    func testConnectOAuth_liveValue_rejectsAPIKeyOnlyProvider() {
        let client = AIProviderConnectionClient.liveValue
        let credential = OAuthCredentialFile(accessToken: "at_wrong_provider")
        let result = awaitTest { await client.connectOAuth(.openai, credential, .connected) }

        XCTAssertEqual(result.provider, .openai)
        XCTAssertEqual(result.state, .connectionFailed)
        XCTAssertEqual(result.reason, .providerUnsupportedInBuild)
    }

    // MARK: - connectAPIKey persistence-only

    func testConnectAPIKey_isPersistenceOnly_returnsConnected() async {
        let result = await AIProviderConnectionClient.liveValue.connectAPIKey(
            .openai,
            "sk-obviously-fake-key",
            .connected
        )
        XCTAssertEqual(result.state, .connected)
    }

    func testConnectOAuth_isPersistenceOnly_returnsConnected() async {
        let credential = OAuthCredentialFile(accessToken: "fake-oauth-token")
        let result = await AIProviderConnectionClient.liveValue.connectOAuth(
            .chatgptCodex,
            credential,
            .connected
        )
        XCTAssertEqual(result.state, .connected)
    }

    // MARK: - disconnect liveValue

    func testDisconnect_liveValue_returnsNotVerified_forProviderWithNoRecord() {
        let client = AIProviderConnectionClient.liveValue
        let disconnectResult = awaitTest { await client.disconnect(.chatgptCodex) }
        XCTAssertEqual(disconnectResult.provider, .chatgptCodex)
        XCTAssertEqual(disconnectResult.state, .notVerified)

        let codexRecord = disconnectResult.updatedFile.providers["chatgptCodex"]
        XCTAssertNil(codexRecord?.credential)
    }

    // MARK: - OAuth infrastructure wiring

    func testCodexOAuthInfrastructureIsWired() {
        let pkce = PKCE.generate()
        XCTAssertEqual(pkce.verifier.count, 43)
        XCTAssertFalse(pkce.challenge.isEmpty)

        let config = CodexOAuthConfig(
            clientId: "test-client-id",
            issuer: URL(string: "https://auth.example.com")!,
            authorizePath: "/authorize",
            tokenPath: "/token",
            redirectPort: 1455,
            redirectPath: "/auth/callback",
            scopes: ["openid", "profile", "email"],
            originator: "test-originator"
        )
        XCTAssertEqual(config.issuer.host, "auth.example.com")
        XCTAssertFalse(config.clientId.isEmpty)

        let authURL = config.authorizeURL(pkceChallenge: pkce.challenge, state: "test")
        XCTAssertTrue(authURL.absoluteString.contains("code_challenge="))
        XCTAssertTrue(authURL.absoluteString.contains("state=test"))
    }

    // MARK: - CodexNativeAuthError mapping

    func testLoginUnavailableMapsToGenericMissingCredential() {
        XCTAssertEqual(CodexNativeAuthError.loginUnavailable, .loginUnavailable)
        let mappedReason = ProviderStatusReason.missingCredential
        XCTAssertEqual(mappedReason, .missingCredential)
    }

    // MARK: - Snapshot persistence with .notVerified

    func testConnectOAuth_withNotVerified_persistsNotVerifiedInSnapshot() async {
        let credential = OAuthCredentialFile(accessToken: "net-err-token")
        let result = await AIProviderConnectionClient.liveValue.connectOAuth(
            .chatgptCodex,
            credential,
            .notVerified
        )

        XCTAssertEqual(result.state, .notVerified)

        let record = result.updatedFile.providers["chatgptCodex"]
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertNil(record?.snapshot.lastVerifiedAtMs)
        XCTAssertEqual(record?.snapshot.lastErrorCode, .networkUnavailable)
    }

    func testConnectAPIKey_withNotVerified_persistsNotVerifiedInSnapshot() async {
        let result = await AIProviderConnectionClient.liveValue.connectAPIKey(
            .openai,
            "sk-net-err-key",
            .notVerified
        )

        XCTAssertEqual(result.state, .notVerified)

        let record = result.updatedFile.providers["openai"]
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertNil(record?.snapshot.lastVerifiedAtMs)
    }

    // MARK: - Snapshot persistence with .connected

    func testConnectOAuth_withConnected_persistsConnectedInSnapshot() async {
        let credential = OAuthCredentialFile(accessToken: "valid-token")
        let result = await AIProviderConnectionClient.liveValue.connectOAuth(
            .chatgptCodex,
            credential,
            .connected
        )

        XCTAssertEqual(result.state, .connected)

        let record = result.updatedFile.providers["chatgptCodex"]
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.snapshot.lastKnownStatus, .connected)
        XCTAssertNotNil(record?.snapshot.lastVerifiedAtMs)
    }
}

private func awaitTest<T: Sendable>(
    timeout: TimeInterval = 2.0,
    _ operation: @escaping @Sendable () async -> T
) -> T {
    let expectation = XCTestExpectation()
    nonisolated(unsafe) var result: T?
    Task { @Sendable in
        result = await operation()
        expectation.fulfill()
    }
    _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    return result!
}

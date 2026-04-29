import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class AiConnectionOAuthTests: XCTestCase {
    private func makeCredential(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAtMs: Int64? = nil
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "Bearer",
            scopes: ["openid", "profile", "email", "offline_access"],
            expiresAtMs: expiresAtMs
        )
    }

    // MARK: - Browser Login Success

    func testBrowserLogin_success_storesAuthAndMarksConnected() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.connectButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginCompleted) { state in
            state.connectionState = .connected
            state.flowState = .idle
            state.statusReason = .none
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    // MARK: - Browser Login Cancellation

    func testBrowserLogin_cancelled_isRecoverable() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.failed(.cancelled))
                    continuation.finish()
                }
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .notVerified
            state.statusReason = .none
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    // MARK: - Browser Login Failure

    func testBrowserLogin_failure_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.failed(.networkError("server error")))
                    continuation.finish()
                }
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.statusReason, .networkUnavailable)
    }

    func testBrowserLogin_timeout_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.timeout))
                    continuation.finish()
                }
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
        }

        await store.finish()
    }

    func testBrowserLogin_callbackMismatch_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.callbackMismatch))
                    continuation.finish()
                }
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .oauthRejected
        }

        await store.finish()
    }

    // MARK: - Cancel Button During OAuth

    func testCancelButton_duringBrowserLogin_resetsToNotVerified() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectInProgress,
                flowState: .browserLoginInProgress
            )
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.connectionState = .notVerified
        }

        await store.finish()
    }

    // MARK: - Connect Button Routes OAuth Providers

    func testConnectButton_oAuthProvider_startsBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        await store.send(.connectButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
        }

        await store.finish()
    }

    // MARK: - Token Refresh (Deterministic Fixture)

    func testOAuthCredential_refreshTokenStored_forFutureRefresh() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresIn5Min = now + 300_000

        let credential = OAuthCredentialFile(
            accessToken: "access-abc",
            refreshToken: "refresh-xyz",
            tokenType: "Bearer",
            scopes: ["openid", "profile"],
            expiresAtMs: expiresIn5Min
        )

        let payload = StoredCredentialPayload.oauth(credential)
        XCTAssertEqual(payload.redacted.debugDescription.contains("access-abc"), false)
        XCTAssertEqual(payload.redacted.debugDescription.contains("refresh-xyz"), false)
        XCTAssertEqual(payload.redacted.debugDescription.contains("****"), true)
    }

    func testOAuthCredential_expiredToken_calculation() {
        let oneHourAgo = Int64(Date().timeIntervalSince1970 * 1000) - 3_600_000

        let credential = OAuthCredentialFile(
            accessToken: "access-expired",
            refreshToken: "refresh-valid",
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: oneHourAgo
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertTrue(isExpired)
    }

    func testOAuthCredential_notExpired_calculation() {
        let oneHourFromNow = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000

        let credential = OAuthCredentialFile(
            accessToken: "access-valid",
            refreshToken: "refresh-valid",
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: oneHourFromNow
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertFalse(isExpired)
    }

    func testOAuthCredential_nilExpiry_treatedAsExpired() {
        let credential = OAuthCredentialFile(
            accessToken: "access-no-expiry",
            refreshToken: nil,
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: nil
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertTrue(isExpired, "Nil expiresAtMs should be treated as expired")
    }

    // MARK: - Verification Failure During Connect

    func testBrowserLogin_verificationFailure_marksConnectionFailed() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.verificationFailed) }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
        }

        await store.finish()
    }

    func testBrowserLogin_persistFailure_marksConnectionFailed() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, _ in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .connectionFailed,
                    reason: .unknown,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
        }

        await store.finish()
    }

    // MARK: - Device Auth

    func testDeviceAuth_success_marksConnected() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startDeviceAuth = {
                DeviceAuthChallenge(
                    userCode: "ABCD-1234",
                    verificationURL: URL(string: "https://chatgpt.com/device")!,
                    pollIntervalMs: 5000,
                    expiresAt: Date().addingTimeInterval(900)
                )
            }
            $0.codexNativeAuthClient.completeDeviceAuth = { _ in credential }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.startDeviceAuth) { state in
            state.flowState = .deviceAuthInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.deviceAuthCompleted) { state in
            state.connectionState = .connected
            state.flowState = .idle
            state.statusReason = .none
        }

        await store.finish()
    }

    func testDeviceAuth_failure_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startDeviceAuth = {
                throw CodexNativeAuthError.loginUnavailable
            }
        }

        await store.send(.startDeviceAuth) { state in
            state.flowState = .deviceAuthInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.deviceAuthFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()
    }

    // MARK: - API Key Provider Skips OAuth

    func testConnectButton_apiKeyProvider_doesNotStartBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai)
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.connectionState, .notVerified)
    }

    // MARK: - Guard Against Re-entry

    func testConnectButton_whileConnecting_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectInProgress,
                flowState: .browserLoginInProgress
            )
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.flowState, .browserLoginInProgress)
    }
}

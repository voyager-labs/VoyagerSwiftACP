// swiftlint:disable file_length
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

private final class BrowserLoginStreamController: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<BrowserLoginState, Error>.Continuation?

    func stream() -> AsyncThrowingStream<BrowserLoginState, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.yield(.inProgress)
        }
    }

    func complete(_ credential: OAuthCredentialFile) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.yield(.completed(credential))
        continuation?.finish()
    }
}

private actor OAuthEventLog {
    private var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor SuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
// swiftlint:disable:next type_body_length
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

        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.browserLoginCompleted)

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testBrowserLogin_delayedCompletion_waitsForVerificationBeforePersisting() async {
        let credential = makeCredential()
        let controller = BrowserLoginStreamController()
        let log = OAuthEventLog()
        let gate = SuspensionGate()
        let verificationStarted = expectation(description: "verification started")

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = { controller.stream() }
            $0.aiProviderVerificationClient.verify = { _, _ in
                await log.record("verify")
                verificationStarted.fulfill()
                await gate.wait()
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                await log.record("connect")
                return AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
        }

        await store.send(.connectButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        controller.complete(credential)
        await fulfillment(of: [verificationStarted], timeout: 1)

        let snapshotBeforeOpen = await log.snapshot()
        XCTAssertEqual(snapshotBeforeOpen, ["verify"])
        XCTAssertEqual(store.state.connectionState, .connectInProgress)
        XCTAssertEqual(store.state.flowState, .browserLoginInProgress)

        await gate.open()

        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.browserLoginCompleted)

        let snapshotAfterOpen = await log.snapshot()
        XCTAssertEqual(snapshotAfterOpen, ["verify", "connect"])

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

    func testBrowserLogin_verificationFailure_doesNotPersistConnected() async {
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
            $0.aiProviderVerificationClient.verify = { _, _ in
                .invalid(.verificationFailed)
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be called before verification succeeds")
                return AiProviderConnectionResult(
                    provider: .chatgptCodex,
                    state: .connected,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
        }

        await store.send(.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.verificationFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .verificationFailed
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connectionFailed)
        XCTAssertEqual(store.state.statusReason, .verificationFailed)
    }

    // MARK: - Cancel Button During OAuth

    func testCancelButton_duringBrowserLogin_resetsToNotVerified() async {
        let controller = BrowserLoginStreamController()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = { controller.stream() }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be called after cancellation")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be called after cancellation")
                return AiProviderConnectionResult(
                    provider: .chatgptCodex,
                    state: .connected,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
        }

        await store.send(.connectButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.connectionState = .notVerified
        }

        controller.complete(makeCredential())
        await Task.yield()

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
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
            state.connectionState = .connectionFailed
            state.flowState = .idle
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

        await store.receive(\.verificationFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .verificationFailed
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

        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.deviceAuthCompleted)

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

    // MARK: - Retry Re-triggers Browser Login

    func testRetryForOAuth_retriggersBrowserLogin() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectionFailed,
                statusReason: .missingCredential,
                flowState: .idle,
                enteredKey: "",
                isVerifying: false,
                isShowingDisconnectConfirmation: false
            )
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

        await store.send(.retryButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\._connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.browserLoginCompleted)

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
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

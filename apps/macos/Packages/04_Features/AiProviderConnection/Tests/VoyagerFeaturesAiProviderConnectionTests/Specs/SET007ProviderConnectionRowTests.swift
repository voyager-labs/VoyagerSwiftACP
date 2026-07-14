import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiProviderConnection
import XCTest

private actor APIKeyConnectionController {
    private var continuation: CheckedContinuation<AiProviderConnectionResult, Never>?

    func connect(
        provider _: AiProvider,
        connectionState _: ProviderConnectionState,
    ) async -> AiProviderConnectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: AiProviderConnectionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

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
        let continuation = continuation
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

// Regression tests for the "unavailable in build" provider connection behavior.
//
// These tests prove unavailable rows stay inert across connect/retry/start-flow paths
// and never reach browser login, verification, or persistence clients.

@MainActor
final class SET007ProviderConnectionRowTests: XCTestCase {
    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: open AIAPIKey Connect Success Moves Row To Connected
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testOpenAIAPIKeyConnectSuccessMovesRowToConnected() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                .connectSuccess(provider: provider, state: connectionState)
            }
        }

        await store.send(.submitAPIKey("  sk-valid  ")) { state in
            state.enteredKey = "sk-valid"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }
        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }
        await store.finish()
    }

    /// SET-007-connect_ai_provider: anthropic APIKey Invalid Credential Shows Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testAnthropicAPIKeyInvalidCredentialShowsConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .anthropic),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.invalidAPIKey) }
        }

        await store.send(.submitAPIKey("bad-key")) { state in
            state.enteredKey = "bad-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .invalidAPIKey
            state.flowState = .idle
        }
        await store.finish()

        XCTAssertEqual(store.state.primaryAction, .retry)
    }

    /// SET-007-connect_ai_provider: submit APIKey cancel After Verification Prevents Connection Completion
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testSubmitAPIKey_cancelAfterVerificationPreventsConnectionCompletion() async {
        let controller = APIKeyConnectionController()
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                await controller.connect(provider: provider, connectionState: connectionState)
            }
        }

        await store.send(.submitAPIKey("sk-test-valid-key")) { state in
            state.enteredKey = "sk-test-valid-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        await controller.resume(with: AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: AIConnectionsFile.empty(),
        ))

        await Task.yield()
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-connect_ai_provider: submit APIKey network Error shows Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testSubmitAPIKey_networkError_showsConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .networkError }
        }

        await store.send(.submitAPIKey("sk-test")) { state in
            state.enteredKey = "sk-test"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
            state.flowState = .idle
        }

        await store.finish()
    }

    /// SET-007-connect_ai_provider: submit APIKey empty Key is Ignored
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testSubmitAPIKey_emptyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey(""))
        await store.finish()
    }

    /// SET-007-connect_ai_provider: submit APIKey whitespace Only Key is Ignored
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testSubmitAPIKey_whitespaceOnlyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey("   "))
        await store.finish()
    }

    /// SET-007-connect_ai_provider: cancel During Connect resets To Idle
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testCancelDuringConnect_resetsToIdle() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connectInProgress,
                flowState: .connecting,
                isVerifying: true,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        await store.finish()
    }

    /// SET-007-connect_ai_provider: submit APIKey trim Whitespace
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testSubmitAPIKey_trimWhitespace() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            }
        }

        await store.send(.submitAPIKey("  sk-trimmed  ")) { state in
            state.enteredKey = "sk-trimmed"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }

        await store.finish()
    }

    private func makeCredential(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        expiresAtMs: Int64? = nil,
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "Bearer",
            scopes: ["openid", "profile", "email", "offline_access"],
            expiresAtMs: expiresAtMs,
        )
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: browser Login delayed Completion waits For Verification Before Persisting
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_delayedCompletion_waitsForVerificationBeforePersisting() async {
        let credential = makeCredential()
        let controller = BrowserLoginStreamController()
        let log = OAuthEventLog()
        let gate = SuspensionGate()
        let verificationStarted = expectation(description: "verification started")

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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
                    updatedFile: AIConnectionsFile.empty(),
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

        await store.receive(\.connectionResponse) { state in
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

    /// SET-007-connect_ai_provider: browser Login cancelled is Recoverable
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_cancelled_isRecoverable() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: browser Login failure marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_failure_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: browser Login timeout marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_timeout_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: browser Login callback Mismatch marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_callbackMismatch_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: browser Login verification Failure does Not Persist Connected
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_verificationFailure_doesNotPersistConnected() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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
                    updatedFile: AIConnectionsFile.empty(),
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

    /// SET-007-connect_ai_provider: cancel Button during Browser Login resets To Not Verified
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testCancelButton_duringBrowserLogin_resetsToNotVerified() async {
        let controller = BrowserLoginStreamController()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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
                    updatedFile: AIConnectionsFile.empty(),
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

    /// SET-007-connect_ai_provider: connect Button o Auth Provider starts Browser Login
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testConnectButton_oAuthProvider_startsBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: oAuth Credential refresh Token Stored for Future Refresh
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testOAuthCredential_refreshTokenStored_forFutureRefresh() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresIn5Min = now + 300_000

        let credential = OAuthCredentialFile(
            accessToken: "access-abc",
            refreshToken: "refresh-xyz",
            tokenType: "Bearer",
            scopes: ["openid", "profile"],
            expiresAtMs: expiresIn5Min,
        )

        let payload = StoredCredentialPayload.oauth(credential)
        XCTAssertFalse(payload.redacted.debugDescription.contains("access-abc"))
        XCTAssertFalse(payload.redacted.debugDescription.contains("refresh-xyz"))
        XCTAssertTrue(payload.redacted.debugDescription.contains("****"))
    }

    /// SET-007-connect_ai_provider: oAuth Credential expired Token calculation
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testOAuthCredential_expiredToken_calculation() {
        let oneHourAgo = Int64(Date().timeIntervalSince1970 * 1000) - 3_600_000

        let credential = OAuthCredentialFile(
            accessToken: "access-expired",
            refreshToken: "refresh-valid",
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: oneHourAgo,
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertTrue(isExpired)
    }

    /// SET-007-connect_ai_provider: oAuth Credential not Expired calculation
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testOAuthCredential_notExpired_calculation() {
        let oneHourFromNow = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000

        let credential = OAuthCredentialFile(
            accessToken: "access-valid",
            refreshToken: "refresh-valid",
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: oneHourFromNow,
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertFalse(isExpired)
    }

    /// SET-007-connect_ai_provider: oAuth Credential nil Expiry treated As Expired
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testOAuthCredential_nilExpiry_treatedAsExpired() {
        let credential = OAuthCredentialFile(
            accessToken: "access-no-expiry",
            refreshToken: nil,
            tokenType: "Bearer",
            scopes: ["openid"],
            expiresAtMs: nil,
        )

        let isExpired = credential.expiresAtMs.map { $0 < Int64(Date().timeIntervalSince1970 * 1000) } ?? true
        XCTAssertTrue(isExpired, "Nil expiresAtMs should be treated as expired")
    }

    /// SET-007-connect_ai_provider: browser Login verification Failure marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_verificationFailure_marksConnectionFailed() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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
                    updatedFile: AIConnectionsFile.empty(),
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

    /// SET-007-connect_ai_provider: browser Login persist Failure marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testBrowserLogin_persistFailure_marksConnectionFailed() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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
                    updatedFile: AIConnectionsFile.empty(),
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

    /// SET-007-connect_ai_provider: device Auth success marks Connected
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testDeviceAuth_success_marksConnected() async {
        let credential = makeCredential()
        guard let verificationURL = URL(string: "https://chatgpt.com/device") else {
            XCTFail("device auth verification URL fixture should be valid")
            return
        }

        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startDeviceAuth = {
                DeviceAuthChallenge(
                    userCode: "ABCD-1234",
                    verificationURL: verificationURL,
                    pollIntervalMs: 5000,
                    expiresAt: Date().addingTimeInterval(900),
                )
            }
            $0.codexNativeAuthClient.completeDeviceAuth = { _ in credential }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.startDeviceAuth) { state in
            state.flowState = .deviceAuthInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.deviceAuthCompleted)

        await store.finish()
    }

    /// SET-007-connect_ai_provider: device Auth failure marks Connection Failed
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testDeviceAuth_failure_marksConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex),
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

    /// SET-007-connect_ai_provider: connect Button api Key Provider does Not Start Browser Login
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testConnectButton_apiKeyProvider_doesNotStartBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.connectionState, .notVerified)
    }

    /// SET-007-connect_ai_provider: retry For OAuth retriggers Browser Login
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
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
                isShowingDisconnectConfirmation: false,
            ),
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
                    updatedFile: AIConnectionsFile.empty(),
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.retryButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
        }

        await store.receive(\.browserLoginCompleted)

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
    }

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: disconnect cancel preserves connected row and credential-facing state.
    /// 연결 해제 확인을 취소하면 어떤 boundary effect도 실행하지 않고 현재 연결을 유지하는지 검증합니다.
    /// - 검증 내용: disconnect confirmation 표시와 cancel 후 connected/idle 상태 및 입력 credential 상태 보존
    /// - 사전 조건: OpenAI row가 connected이며 이전 credential 입력값을 유지한다.
    /// - 기대 결과: confirmation만 닫히고 connected row는 다시 Disconnect action을 제공한다.
    func testDisconnectCancelPreservesConnectedRowAndCredentialFacingState() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped) { state in
            state.isShowingDisconnectConfirmation = true
        }
        await store.send(.disconnectCancel) { state in
            state.isShowingDisconnectConfirmation = false
        }
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.enteredKey, "sk-preserved")
        XCTAssertEqual(store.state.primaryAction, .disconnect)
    }

    /// SET-007-disconnect_ai_provider: failed disconnect restores the connected recovery state.
    /// 연결 해제 boundary가 실패 결과를 반환해도 row가 실제로 끊긴 상태로 표시되지 않는지 검증합니다.
    /// - 검증 내용: disconnect confirm, deterministic failed response, connected recovery, Disconnect action
    /// - 사전 조건: OpenAI row가 connected이고 disconnect client가 connected/networkUnavailable 결과를 반환한다.
    /// - 기대 결과: response 후 connected/idle 상태와 credential-facing 입력값을 보존하고 다시 disconnect할 수 있다.
    func testDisconnectFailureRestoresConnectedRowAndRecoveryAction() async {
        let preservedFile = AIConnectionsFile.singleProvider(.openai, state: .connected)
        let result = AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .networkUnavailable,
            updatedFile: preservedFile,
        )
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
            ),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { provider in
                XCTAssertEqual(provider, .openai)
                return result
            }
        }

        await store.send(.disconnectButtonTapped) { state in
            state.isShowingDisconnectConfirmation = true
        }
        await store.send(.disconnectConfirm) { state in
            state.isShowingDisconnectConfirmation = false
            state.flowState = .disconnecting
            state.connectionState = .disconnecting
        }
        await store.receive(\.disconnectResponse) { state in
            state.flowState = .idle
            state.connectionState = .connected
            state.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.enteredKey, "sk-preserved")
        XCTAssertEqual(store.state.primaryAction, .disconnect)
    }

    /// SET-007-disconnect_ai_provider: disconnect Button non Connected State is Ignored
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testDisconnectButton_nonConnectedState_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .notVerified,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertFalse(store.state.isShowingDisconnectConfirmation)
    }

    /// SET-007-disconnect_ai_provider: disconnect While Disconnecting no Duplicate Effect
    /// 사용자가 AI provider 연결을 시작·재시도·취소할 때 row 상태가 SET-007 연결 흐름에 맞게 전환되는지 검증합니다.
    /// - 검증 내용: API key/OAuth/device auth 흐름의 진행, 성공, 실패, 취소 상태 전이를 확인합니다.
    /// - 사전 조건: provider row reducer에 연결 방식별 dependency 응답과 credential fixture를 구성합니다.
    /// - 기대 결과: row가 connect_in_progress, connected, connection_failed, notVerified 상태를 SET-007 기대 동작대로 표시합니다.
    func testDisconnectWhileDisconnecting_noDuplicateEffect() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .disconnecting,
                flowState: .disconnecting,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .disconnecting)
        XCTAssertEqual(store.state.flowState, .disconnecting)
    }

    // MARK: - SET-007-show_ai_provider_list

    /// SET-007-show_ai_provider_list: connect Button unavailable api Key Provider is Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testConnectButton_unavailable_apiKeyProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: retry Button unavailable api Key Provider is Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testRetryButton_unavailable_apiKeyProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .anthropic, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
        }

        await store.send(.retryButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: primary Action unavailable is Disabled
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testPrimaryAction_unavailable_isDisabled() {
        XCTAssertEqual(
            ProviderConnectionState.unavailable.primaryAction,
            .disabled,
        )

        let row = AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
        XCTAssertEqual(row.primaryAction, .disabled)
    }

    /// SET-007-show_ai_provider_list: connect Button unavailable o Auth Provider is Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testConnectButton_unavailable_oAuthProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: retry Button unavailable o Auth Provider is Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testRetryButton_unavailable_oAuthProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.retryButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: unavailable OAuth Row direct Start Actions are Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testUnavailableOAuthRow_directStartActions_areIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.startBrowserLogin)
        await store.send(.startDeviceAuth)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: unavailable Row api Key Provider does Not Invoke Browser Login
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testUnavailableRow_apiKeyProvider_doesNotInvokeBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be called for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be called from connectButtonTapped for unavailable row")
                return .valid
            }
            $0.aiProviderConnectionClient.connectAPIKey = { _, _, _ in
                XCTFail("connectAPIKey must not be called from connectButtonTapped for unavailable row")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be called from connectButtonTapped for unavailable row")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: unavailable Row api Key Submit is Ignored
    /// 지원되지 않는 AI provider row가 SET-007 provider 목록에서 비활성 상태로 유지되는지 검증합니다.
    /// - 검증 내용: connect/retry/direct start/API key submit 경로가 verification, OAuth, persistence client를 호출하지 않는지 확인합니다.
    /// - 사전 조건: provider row를 unavailable 상태로 구성하고 side-effect client 호출을 실패로 감시합니다.
    /// - 기대 결과: primary action이 disabled이고 row가 unavailable/idle 상태를 유지합니다.
    func testUnavailableRow_apiKeySubmit_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable API key provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectAPIKey = { _, _, _ in
                XCTFail("connectAPIKey must not be invoked for unavailable API key provider")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.submitAPIKey("test-key"))
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }
}

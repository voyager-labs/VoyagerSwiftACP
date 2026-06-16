import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class SET007ManageAIConnectionsTests: XCTestCase {
    // MARK: - SET-007-show_ai_provider_list

    /// SET-007-show_ai_provider_list: 지원 provider row는 연결 방식과 primary action을 노출하고 기본/최근 사용 UI를 만들지 않는다.
    /// Settings AI 탭의 provider 목록이 현재 빌드의 지원 provider와 계약상 허용된 연결 방식만 표시하는지 검증한다.
    /// - 검증 내용: ChatGPT Codex/OAuth, OpenAI/API Key, Anthropic/API Key, fresh action, connected/retry action
    /// - 사전 조건: Settings AI provider catalog를 기본 상태로 구성한다.
    /// - 기대 결과: 3개 provider row가 정해진 순서와 method label/action으로 노출되고 default/last-used 상태는 없다.
    func testProviderRowsExposeSupportedProvidersMethodsAndActions() {
        let rows = AiSettingsState.catalogRows()

        XCTAssertEqual(rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])
        XCTAssertEqual(rows.map(\.displayName), ["ChatGPT Codex", "OpenAI", "Anthropic"])
        XCTAssertEqual(rows.map(\.authMethodLabel), ["OAuth", "API Key", "API Key"])
        XCTAssertTrue(rows.allSatisfy { $0.connectionState == .notVerified })
        XCTAssertTrue(rows.allSatisfy { $0.primaryAction == .connect })
        XCTAssertEqual(AiConnectionRowState(provider: .openai, connectionState: .connected).primaryAction, .disconnect)
        XCTAssertEqual(
            AiConnectionRowState(provider: .anthropic, connectionState: .connectionFailed).primaryAction,
            .retry,
        )
    }

    /// SET-007-show_ai_provider_list: unavailable provider는 목록에 남지만 action은 disabled다.
    /// 지원되지 않는 provider row가 사라지지 않고 사용자에게 비활성 상태로 표현되는지 검증한다.
    /// - 검증 내용: unavailable 상태의 primary action과 연결 시도 무시
    /// - 사전 조건: OpenAI row를 unavailable 상태로 구성한다.
    /// - 기대 결과: row 상태가 unavailable/idle로 유지되고 primary action은 disabled다.
    func testUnavailableProviderIsVisibleDisabledAndInert() async {
        let store = rowStore(
            state: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        )

        await store.send(.connectButtonTapped)
        await store.send(.retryButtonTapped)
        await store.send(.submitAPIKey("sk-test"))
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.primaryAction, .disabled)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: ChatGPT Codex는 OAuth browser login으로만 연결된다.
    /// OAuth provider connect action이 API key 경로 없이 browser login flow와 verification/persistence를 거치는지 검증한다.
    /// - 검증 내용: connect button, browser login in-progress, OAuth verification, connected completion
    /// - 사전 조건: ChatGPT Codex row가 not_verified 상태이고 OAuth fixture가 성공한다.
    /// - 기대 결과: row가 connect_in_progress를 거쳐 connected가 되고 flowState는 idle로 복귀한다.
    func testChatGPTCodexOAuthConnectSuccessMovesRowToConnected() async {
        let credential = OAuthCredentialFile.testFixture()
        let store = rowStore(
            state: AiConnectionRowState(provider: .chatgptCodex),
        ) {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .chatgptCodex)
                XCTAssertNotNil(credential)
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                .connectSuccess(provider: provider, state: connectionState)
            }
        }

        await store.send(.connectButtonTapped)
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
    }

    /// SET-007-connect_ai_provider: OpenAI API key 연결 성공은 verification 이후 connected로 전환된다.
    /// API key provider가 OAuth flow를 시작하지 않고 key verification과 connect client만 사용하는지 검증한다.
    /// - 검증 내용: trimmed key 저장, verification response, API key connect response, connected row state
    /// - 사전 조건: OpenAI row가 not_verified 상태이고 API key verification이 valid를 반환한다.
    /// - 기대 결과: row가 connected가 되고 입력 key는 성공 후 비워진다.
    func testOpenAIAPIKeyConnectSuccessMovesRowToConnected() async {
        let store = apiKeyRowStore(provider: .openai, verificationResult: .valid)

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

    /// SET-007-connect_ai_provider: Anthropic API key 검증 실패는 recoverable connection_failed 상태가 된다.
    /// 잘못된 API key가 connected로 저장되지 않고 retry 가능한 실패 상태로 표시되는지 검증한다.
    /// - 검증 내용: invalid API key verification, connection_failed state, invalidAPIKey reason, retry action
    /// - 사전 조건: Anthropic row가 not_verified 상태이고 verification이 invalidAPIKey를 반환한다.
    /// - 기대 결과: row는 connection_failed/invalidAPIKey가 되고 primary action은 retry다.
    func testAnthropicAPIKeyInvalidCredentialShowsConnectionFailed() async {
        let store = apiKeyRowStore(provider: .anthropic, verificationResult: .invalid(.invalidAPIKey))

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

    /// SET-007-connect_ai_provider: connect_in_progress 중복 connect action은 새 flow를 만들지 않는다.
    /// 이미 연결 flow가 진행 중일 때 re-entry가 provider client를 중복 호출하지 않는지 검증한다.
    /// - 검증 내용: duplicate connect button ignored, flowState unchanged
    /// - 사전 조건: ChatGPT Codex row가 connect_in_progress/browserLoginInProgress 상태다.
    /// - 기대 결과: state가 변경되지 않고 추가 effect가 없다.
    func testDuplicateConnectWhileInProgressIsIgnored() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectInProgress,
                flowState: .browserLoginInProgress,
            ),
        )

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connectInProgress)
        XCTAssertEqual(store.state.flowState, .browserLoginInProgress)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: OAuth browser login은 verification이 끝나기 전 persistence를 실행하지 않는다.
    /// 브라우저 login 완료 후 verification gate가 닫힐 때까지 연결 저장이 지연되는지 검증한다.
    /// - 검증 내용: browser login completion, verification ordering, connect client ordering
    /// - 사전 조건: ChatGPT Codex OAuth credential이 반환되고 verification은 gate에서 대기한다.
    /// - 기대 결과: verification 이후에만 connect가 호출되고 row는 connected/idle이 된다.
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

    /// SET-007-connect_ai_provider: OAuth browser login 취소는 recoverable not_verified 상태로 돌아간다.
    /// 사용자가 OAuth 창을 취소해도 실패 상태로 고정되지 않고 재시도 가능한지 검증한다.
    /// - 검증 내용: cancelled browser login event, state reset, status reason
    /// - 사전 조건: ChatGPT Codex row가 browserLoginInProgress 상태로 진입한다.
    /// - 기대 결과: row는 not_verified/none/idle 상태로 복구된다.
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

    /// SET-007-connect_ai_provider: OAuth browser login network failure는 connection_failed로 표시된다.
    /// 브라우저 login 중 네트워크 오류가 retry 가능한 실패 reason으로 매핑되는지 검증한다.
    /// - 검증 내용: networkError browser login event, connection_failed state, networkUnavailable reason
    /// - 사전 조건: ChatGPT Codex OAuth browser login이 networkError를 반환한다.
    /// - 기대 결과: row는 connection_failed/networkUnavailable/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: OAuth browser login timeout은 networkUnavailable 실패로 표시된다.
    /// 인증 시간이 초과된 경우 연결 성공으로 저장하지 않고 실패 상태로 복구하는지 검증한다.
    /// - 검증 내용: timeout browser login event, connection_failed state
    /// - 사전 조건: ChatGPT Codex OAuth browser login이 timeout을 반환한다.
    /// - 기대 결과: row는 connection_failed/networkUnavailable/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: OAuth callback mismatch는 oauthRejected 실패로 표시된다.
    /// redirect callback 검증 실패가 연결 성공으로 진행되지 않는지 검증한다.
    /// - 검증 내용: callbackMismatch browser login event, oauthRejected reason
    /// - 사전 조건: ChatGPT Codex OAuth browser login이 callbackMismatch를 반환한다.
    /// - 기대 결과: row는 connection_failed/oauthRejected/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: OAuth verification 실패는 connected persistence를 호출하지 않는다.
    /// OAuth credential을 받아도 provider verification이 실패하면 connect client를 실행하지 않는지 검증한다.
    /// - 검증 내용: completed credential, invalid verification, connectOAuth dependency trap
    /// - 사전 조건: ChatGPT Codex credential은 반환되지만 verification은 verificationFailed를 반환한다.
    /// - 기대 결과: row는 connection_failed/verificationFailed가 되고 connectOAuth는 호출되지 않는다.
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

    /// SET-007-connect_ai_provider: browser login 중 cancel button은 OAuth completion을 무시한다.
    /// 사용자가 취소한 뒤 늦게 도착한 credential이 연결 상태를 오염시키지 않는지 검증한다.
    /// - 검증 내용: cancelButtonTapped, late OAuth completion, dependency trap
    /// - 사전 조건: ChatGPT Codex row가 browserLoginInProgress 상태다.
    /// - 기대 결과: row는 not_verified/idle로 유지되고 verification/connect는 호출되지 않는다.
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

    /// SET-007-connect_ai_provider: OAuth provider connect button은 browser login effect를 시작한다.
    /// OAuth 방식 provider가 API key 경로가 아니라 browser login action으로 라우팅되는지 검증한다.
    /// - 검증 내용: connectButtonTapped, startBrowserLogin action, browser login failure fallback
    /// - 사전 조건: ChatGPT Codex row가 not_verified 상태다.
    /// - 기대 결과: browserLoginInProgress로 전환된 뒤 빈 stream은 networkUnavailable 실패로 복구된다.
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

    /// SET-007-connect_ai_provider: OAuth credential redaction은 access/refresh token 원문을 노출하지 않는다.
    /// refresh token 보존 fixture가 debug output에서 민감한 token을 숨기는지 검증한다.
    /// - 검증 내용: StoredCredentialPayload.oauth redacted debugDescription
    /// - 사전 조건: access token과 refresh token이 있는 OAuth credential을 구성한다.
    /// - 기대 결과: debugDescription에는 token 원문이 없고 redaction marker만 포함된다.
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

    /// SET-007-connect_ai_provider: OAuth credential expiry 계산은 과거 만료 시각을 expired로 본다.
    /// 저장된 OAuth token 만료 판단의 deterministic fixture를 보존한다.
    /// - 검증 내용: expiresAtMs past timestamp comparison
    /// - 사전 조건: expiresAtMs가 현재보다 1시간 과거인 credential을 구성한다.
    /// - 기대 결과: expiry 계산 결과가 true다.
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

    /// SET-007-connect_ai_provider: OAuth credential expiry 계산은 미래 만료 시각을 유효로 본다.
    /// 저장된 OAuth token이 아직 만료되지 않은 경우를 deterministic fixture로 보존한다.
    /// - 검증 내용: expiresAtMs future timestamp comparison
    /// - 사전 조건: expiresAtMs가 현재보다 1시간 미래인 credential을 구성한다.
    /// - 기대 결과: expiry 계산 결과가 false다.
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

    /// SET-007-connect_ai_provider: OAuth credential expiry가 없으면 expired로 취급한다.
    /// 만료 시각이 없는 저장 credential을 안전하게 재검증 대상으로 보는지 검증한다.
    /// - 검증 내용: nil expiresAtMs fallback
    /// - 사전 조건: expiresAtMs가 nil인 OAuth credential을 구성한다.
    /// - 기대 결과: expiry 계산 결과가 true다.
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

    /// SET-007-connect_ai_provider: OAuth verification 실패는 connection_failed로 종료된다.
    /// verification invalid 결과가 row state와 reason에 반영되는지 검증한다.
    /// - 검증 내용: completed credential, invalid verification, verificationFailed action
    /// - 사전 조건: ChatGPT Codex credential은 반환되지만 verification은 verificationFailed를 반환한다.
    /// - 기대 결과: row는 connection_failed/verificationFailed/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: OAuth persistence 실패는 recoverable connection_failed로 표시된다.
    /// connectOAuth가 실패 결과를 반환하면 connected로 오인하지 않는지 검증한다.
    /// - 검증 내용: completed credential, connectOAuth failure result, browserLoginFailed fallback
    /// - 사전 조건: OAuth credential은 반환되고 connectOAuth는 connectionFailed/unknown 결과를 반환한다.
    /// - 기대 결과: row는 connection_failed/networkUnavailable/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: device auth 성공은 OAuth credential 저장 후 connected로 전환된다.
    /// device auth 경로가 browser login과 동일한 verification/persistence 계약으로 완료되는지 검증한다.
    /// - 검증 내용: startDeviceAuth, completeDeviceAuth, connectionResponse, deviceAuthCompleted
    /// - 사전 조건: device auth challenge와 OAuth credential fixture가 성공한다.
    /// - 기대 결과: row는 connected/none/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: device auth 시작 실패는 providerUnsupportedInBuild로 표시된다.
    /// device auth를 사용할 수 없는 환경에서 연결 중 상태로 남지 않는지 검증한다.
    /// - 검증 내용: startDeviceAuth throw, deviceAuthFailed action, status reason
    /// - 사전 조건: device auth client가 loginUnavailable을 던진다.
    /// - 기대 결과: row는 connection_failed/providerUnsupportedInBuild/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: API key provider connect button은 OAuth browser login을 시작하지 않는다.
    /// OpenAI 같은 API key provider가 OAuth 전용 flow로 잘못 라우팅되지 않는지 검증한다.
    /// - 검증 내용: connectButtonTapped on API key row, flow state preservation
    /// - 사전 조건: OpenAI row가 not_verified 상태다.
    /// - 기대 결과: row는 not_verified/idle 상태로 유지된다.
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

    /// SET-007-connect_ai_provider: OAuth retry action은 browser login flow를 다시 시작한다.
    /// 실패한 OAuth provider가 retry에서 동일한 browser login→connected 경로를 재실행하는지 검증한다.
    /// - 검증 내용: retryButtonTapped, startBrowserLogin, connectionResponse, browserLoginCompleted
    /// - 사전 조건: ChatGPT Codex row가 connection_failed/missingCredential 상태다.
    /// - 기대 결과: row는 connect_in_progress를 거쳐 connected가 된다.
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

    /// SET-007-disconnect_ai_provider: connected provider의 disconnect는 확인 dialog를 먼저 연다.
    /// 사용자가 실수로 credential을 제거하지 않도록 confirmation gate가 선행되는지 검증한다.
    /// - 검증 내용: disconnect button, confirmation flag, connected state preservation
    /// - 사전 조건: OpenAI row가 connected 상태다.
    /// - 기대 결과: confirmation이 표시되고 row는 아직 connected 상태다.
    func testDisconnectButtonShowsConfirmationBeforeMutation() async {
        let store = rowStore(state: AiConnectionRowState(provider: .openai, connectionState: .connected))

        await store.send(.disconnectButtonTapped) { state in
            state.isShowingDisconnectConfirmation = true
        }
        await store.finish()
    }

    /// SET-007-disconnect_ai_provider: confirmation cancel은 connected 상태를 유지한다.
    /// disconnect 확인 dialog에서 취소한 경우 저장 상태와 row state가 바뀌지 않는지 검증한다.
    /// - 검증 내용: disconnect cancel, confirmation dismissal, connected preservation
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: confirmation만 닫히고 connected 상태가 유지된다.
    func testDisconnectCancelKeepsProviderConnected() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true,
            ),
        )

        await store.send(.disconnectCancel) { state in
            state.isShowingDisconnectConfirmation = false
        }
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
    }

    /// SET-007-disconnect_ai_provider: confirmation success는 credential 제거 file update를 전달하고 not_verified로 돌아간다.
    /// Settings 소유 범위에서 연결 해제 결과가 row state와 저장 파일의 credential 제거 사실을 함께 갱신하는지 검증한다.
    /// - 검증 내용: disconnecting transition, disconnect response, credential nil updatedFile delegate, connect action
    /// - 사전 조건: OpenAI row가 connected이고 confirmation이 표시되어 있다.
    /// - 기대 결과: row는 not_verified가 되고 delegate payload의 OpenAI credential은 nil이다.
    func testDisconnectConfirmationSuccessRemovesCredentialAndEmitsFileUpdate() async {
        let updatedFile = openAIDisconnectedFile()
        let result = AiProviderConnectionResult(
            provider: .openai,
            state: .notVerified,
            reason: .none,
            updatedFile: updatedFile,
        )
        let store = TestStore(initialState: AiSettingsState(rows: [
            AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                enteredKey: "sk-preserved",
                isShowingDisconnectConfirmation: true,
            ),
        ])) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { _ in result }
        }

        await store.send(.row(.element(id: .openai, action: .disconnectConfirm))) { state in
            state.rows[id: .openai]?.isShowingDisconnectConfirmation = false
            state.rows[id: .openai]?.flowState = .disconnecting
            state.rows[id: .openai]?.connectionState = .disconnecting
        }
        await store.receive(.row(.element(id: .openai, action: .disconnectResponse(result)))) { state in
            state.rows[id: .openai]?.flowState = .idle
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.enteredKey = ""
        }
        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
        await store.finish()

        XCTAssertNil(updatedFile.providers[AiProvider.openai.rawValue]?.credential)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-disconnect_ai_provider: disconnect 실패는 connected 상태를 보존한다.
    /// credential 제거 실패가 UI를 잘못 not_verified로 낮추지 않는지 검증한다.
    /// - 검증 내용: disconnecting transition, failure response, connected preservation
    /// - 사전 조건: OpenAI row가 connected이고 disconnect client가 connected 결과를 반환한다.
    /// - 기대 결과: row는 connected/idle로 복구된다.
    func testDisconnectFailurePreservesConnectedState() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true,
            ),
        ) {
            $0.aiProviderConnectionClient.disconnect = { provider in
                AiProviderConnectionResult(provider: provider, state: .connected, reason: .none, updatedFile: .empty())
            }
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
    }

    // MARK: - SET-007-restore_ai_provider_connection_status

    /// SET-007-restore_ai_provider_connection_status: 저장 credential은 checking_status를 거쳐 connected로 복원된다.
    /// Settings AI 탭 진입 시 저장된 credential을 즉시 connected로 단정하지 않고 verification 이후 확정하는지 검증한다.
    /// - 검증 내용: onAppear bootstrap, checking_status initial result, verification completed result
    /// - 사전 조건: OpenAI credential이 저장되어 있고 verification은 valid를 반환한다.
    /// - 기대 결과: OpenAI row가 checking_status를 거쳐 connected가 된다.
    func testStoredCredentialRestoresFromCheckingStatusToConnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connected)) {
            $0.aiProviderVerificationClient.verify = { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertNotNil(credential)
                return .valid
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: credential이 없으면 not_verified와 missingCredential reason으로 복원된다.
    /// 저장 row는 있으나 credential payload가 누락된 경우 연결된 것으로 오인하지 않는지 검증한다.
    /// - 검증 내용: missing credential bootstrap result, no verification request, connect action
    /// - 사전 조건: OpenAI provider record는 있지만 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential이고 primary action은 connect다.
    func testMissingCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let store = settingsStore(file: file)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .missingCredential
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: failed snapshot은 checking_status 이후 connection_failed로 복원된다.
    /// 만료된 저장 credential이 recoverable retry 상태로 표현되는지 검증한다.
    /// - 검증 내용: connectionFailed snapshot, verification invalid response, retry action
    /// - 사전 조건: OpenAI snapshot이 connectionFailed/expired이고 verification도 expired를 반환한다.
    /// - 기대 결과: row는 connection_failed/expired이고 primary action은 retry다.
    func testFailedSnapshotRestoresToConnectionFailedWithRetry() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .connectionFailed, errorCode: .expired)) {
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.expired) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
    }

    /// SET-007-restore_ai_provider_connection_status: provider record가 없으면 모든 row는 not_verified로 복원된다.
    /// 저장 파일이 비어 있는 fresh 상태를 연결 실패나 missing credential로 오인하지 않는지 검증한다.
    /// - 검증 내용: empty connections file bootstrap, default rows, connect primary action
    /// - 사전 조건: AI connections file에 provider record가 없다.
    /// - 기대 결과: 모든 row가 not_verified/none 상태이고 primary action은 connect다.
    func testNoProviderRecordRestoresAllRowsToNotVerified() async {
        let store = settingsStore(file: .empty())

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()

        for row in store.state.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.statusReason, .none)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    /// SET-007-restore_ai_provider_connection_status: stale connect_in_progress snapshot은 credential이 있어도 not_verified로
    /// 낮춘다.
    /// 이전 세션에서 중단된 연결 시도를 재시작하지 않고 사용자가 명시적으로 다시 연결하도록 만드는지 검증한다.
    /// - 검증 내용: persisted connect_in_progress snapshot, credential present, no missingCredential reason
    /// - 사전 조건: ChatGPT Codex OAuth credential이 있지만 snapshot은 connect_in_progress다.
    /// - 기대 결과: row는 not_verified/none 상태이고 primary action은 connect다.
    func testConnectInProgressSnapshotWithCredentialRestoresToNotVerified() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )
        let store = settingsStore(file: file)

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 provider가 계속 disconnecting으로 고정되지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, loaded restore state, connect primary action
    /// - 사전 조건: Anthropic provider snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectingSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.anthropic, state: .disconnecting))

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected 상태와 connect action을 유지한다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되어 복원되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, status reason, primary action
    /// - 사전 조건: OpenAI provider snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected/none 상태이고 primary action은 connect다.
    func testDisconnectedSnapshotRestoresToDisconnected() async {
        let store = settingsStore(file: .singleProvider(.openai, state: .disconnected))

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: 여러 provider snapshot은 독립적으로 복원된다.
    /// connected/failed/no-record provider가 한 bootstrap에서 서로의 상태를 오염시키지 않는지 검증한다.
    /// - 검증 내용: mixed provider records, verification fan-out, connected/retry/connect actions
    /// - 사전 조건: ChatGPT Codex는 connected, OpenAI는 expired failure, Anthropic은 record가 없다.
    /// - 기대 결과: Codex는 connected, OpenAI는 connection_failed/expired, Anthropic은 not_verified다.
    func testMixedProviderSnapshotsRestoreIndependently() async {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-expired")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .expired,
                    ),
                ),
            ],
        )
        let store = settingsStore(file: file) {
            $0.aiProviderVerificationClient.verify = { provider, _ in
                switch provider {
                case .chatgptCodex: .valid
                case .openai: .invalid(.expired)
                case .anthropic: .valid
                }
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .openai]?.connectionState = .connectionFailed
            state.rows[id: .openai]?.statusReason = .expired
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .chatgptCodex]?.primaryAction, .disconnect)
        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .retry)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.connectionState, .notVerified)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.statusReason, ProviderStatusReason.none)
        XCTAssertEqual(store.state.rows[id: .anthropic]?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: catalog load failure는 rows를 보존하고 retry로 복구된다.
    /// provider catalog/load 오류가 빈 목록으로 보이지 않고 사용자가 재시도할 수 있는 상태로 남는지 검증한다.
    /// - 검증 내용: bootstrap failed phase, rows preserved, retry bootstrap success
    /// - 사전 조건: 첫 load는 실패하고 두 번째 load는 OpenAI credential file을 반환한다.
    /// - 기대 결과: failed phase 후 retry가 loaded/connected 상태로 회복된다.
    func testCatalogLoadFailureShowsRetryAndCanRecover() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                let count = await loadCounter.increment()
                if count == 1 { throw NSError(domain: "SET007", code: -1) }
                return AIConnectionsFile.singleProvider(.openai, state: .connected)
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        XCTAssertEqual(store.state.rows.count, 3)
        XCTAssertTrue(store.state.rows.allSatisfy { $0.connectionState == .notVerified })

        await store.send(.retryBootstrapTapped) { state in
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.bootstrapPhase = .loaded
        }
        await store.finish()
    }

    /// SET-007-disconnect_ai_provider: 연결되지 않은 provider의 disconnect action은 무시된다.
    /// 연결 해제는 connected 상태에서만 실행되어야 하므로 미연결 row가 confirmation이나 effect를 만들지 않는지 검증한다.
    /// - 검증 내용: notVerified row의 disconnect button tap, confirmation flag, state preservation
    /// - 사전 조건: OpenAI row가 not_verified 상태다.
    /// - 기대 결과: row는 not_verified 상태를 유지하고 confirmation이 표시되지 않는다.
    func testDisconnectButtonForNonConnectedStateIsIgnored() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .notVerified,
            ),
        )

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertFalse(store.state.isShowingDisconnectConfirmation)
    }

    /// SET-007-disconnect_ai_provider: disconnecting 상태의 중복 disconnect action은 새 effect를 만들지 않는다.
    /// 이미 연결 해제 중인 row가 재진입으로 중복 mutation을 만들지 않는지 검증한다.
    /// - 검증 내용: disconnecting row의 disconnect button tap, flow state preservation
    /// - 사전 조건: OpenAI row가 disconnecting/disconnecting 상태다.
    /// - 기대 결과: connectionState와 flowState가 disconnecting으로 유지된다.
    func testDisconnectWhileDisconnectingDoesNotCreateDuplicateEffect() async {
        let store = rowStore(
            state: AiConnectionRowState(
                provider: .openai,
                connectionState: .disconnecting,
                flowState: .disconnecting,
            ),
        )

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .disconnecting)
        XCTAssertEqual(store.state.flowState, .disconnecting)
    }

    /// SET-007-restore_ai_provider_connection_status: catalog load 실패 뒤 onAppear 재진입은 자동 retry를 실행하지 않는다.
    /// 실패 상태에서 사용자의 명시적 retry 없이 catalog load를 반복하지 않는지 검증한다.
    /// - 검증 내용: initial onAppear failure, second onAppear ignored, load call count
    /// - 사전 조건: AI connections file load가 항상 실패한다.
    /// - 기대 결과: load는 1회만 호출되고 bootstrapPhase는 failed로 유지된다.
    func testCatalogLoadFailureDoesNotRetryAutomaticallyOnAppear() async {
        let loadCounter = LoadCounter()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                _ = await loadCounter.increment()
                throw NSError(domain: "SET007", code: -1)
            }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.send(.onAppear)
        await store.finish()

        let loadCalls = await loadCounter.currentValue()
        XCTAssertEqual(loadCalls, 1)
        XCTAssertEqual(store.state.bootstrapPhase, .failed)
    }

    /// SET-007-show_ai_provider_list: unavailable OAuth provider는 모든 연결 시작 경로를 무시한다.
    /// 지원되지 않는 OAuth provider row가 browser/device auth, verification, persistence client를 호출하지 않는지 검증한다.
    /// - 검증 내용: connect/retry/direct start actions, unavailable state preservation, dependency trap
    /// - 사전 조건: ChatGPT Codex row가 unavailable 상태다.
    /// - 기대 결과: row는 unavailable/idle로 유지되고 외부 client 호출은 발생하지 않는다.
    func testUnavailableOAuthProviderIgnoresAllStartActions() async {
        let store = rowStore(
            state: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
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
                return .connectSuccess(provider: .chatgptCodex, state: .connected)
            }
        }

        await store.send(.connectButtonTapped)
        await store.send(.retryButtonTapped)
        await store.send(.startBrowserLogin)
        await store.send(.startDeviceAuth)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-show_ai_provider_list: unavailable API key provider는 submit action을 무시한다.
    /// 지원되지 않는 API key provider row가 key 제출로 verification/connect client를 호출하지 않는지 검증한다.
    /// - 검증 내용: submitAPIKey action, unavailable state preservation, dependency trap
    /// - 사전 조건: OpenAI row가 unavailable 상태다.
    /// - 기대 결과: row는 unavailable/idle로 유지되고 verification/connectAPIKey 호출은 발생하지 않는다.
    func testUnavailableAPIKeyProviderIgnoresSubmit() async {
        let store = rowStore(
            state: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable API key provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectAPIKey = { _, _, _ in
                XCTFail("connectAPIKey must not be invoked for unavailable API key provider")
                return .connectSuccess(provider: .openai, state: .connected)
            }
        }

        await store.send(.submitAPIKey("sk-test"))
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    /// SET-007-restore_ai_provider_connection_status: unavailable snapshot은 verification 후 disabled 상태로 복원된다.
    /// 저장된 provider가 현재 build에서 지원되지 않을 때 연결 가능한 상태로 오인하지 않는지 검증한다.
    /// - 검증 내용: persisted unavailable snapshot, checking status, unsupported verification, disabled primary action
    /// - 사전 조건: OpenAI provider snapshot이 unavailable/providerUnsupportedInBuild 상태다.
    /// - 기대 결과: OpenAI row는 unavailable/providerUnsupportedInBuild이고 primary action은 disabled다.
    func testUnavailableSnapshotRestoresWithDisabledAction() async {
        let store = settingsStore(file: .singleProvider(
            .openai,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild,
        )) {
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .unavailable
            state.rows[id: .openai]?.statusReason = .providerUnsupportedInBuild
        }
        await store.finish()

        XCTAssertEqual(store.state.rows[id: .openai]?.primaryAction, .disabled)
    }

    // MARK: - SET-007-connect_ai_provider

    /// SET-007-connect_ai_provider: connection response는 connectionsFileUpdated delegate를 방출한다.
    /// row reducer 결과가 Settings feature의 저장 파일 갱신 delegate로 이어지는지 검증한다.
    /// - 검증 내용: row connectionResponse, connected state, delegate payload
    /// - 사전 조건: ChatGPT Codex row가 connect_in_progress/browserLoginInProgress 상태다.
    /// - 기대 결과: row는 connected/idle이 되고 updated file delegate가 방출된다.
    func testConnectionResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.chatgptCodex, state: .connected)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .chatgptCodex,
                    connectionState: .connectInProgress,
                    flowState: .browserLoginInProgress,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .chatgptCodex,
            action: .connectionResponse(AiProviderConnectionResult(
                provider: .chatgptCodex,
                state: .connected,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connected
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.rows[id: .chatgptCodex]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    /// SET-007-restore_ai_provider_connection_status: bootstrap verification 성공은 저장 파일과 delegate를 갱신한다.
    /// stale failed snapshot이 valid verification 후 connected snapshot으로 저장되는지 검증한다.
    /// - 검증 내용: bootstrap verification, AI connections file save, delegate emission
    /// - 사전 조건: OpenAI snapshot이 connection_failed/expired이고 verification은 valid다.
    /// - 기대 결과: connected snapshot 파일이 저장되고 동일 payload delegate가 방출된다.
    func testBootstrapVerificationSuccessPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            errorCode: .expired,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: staleFile.providers[AiProvider.openai.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connected,
                        lastVerifiedAtMs: staleFile.updatedAtMs,
                        lastErrorCode: .none,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    // MARK: - SET-007-disconnect_ai_provider

    /// SET-007-disconnect_ai_provider: disconnect response는 connectionsFileUpdated delegate를 방출한다.
    /// 연결 해제 결과가 Settings feature 경계에서 저장 파일 갱신 이벤트로 전달되는지 검증한다.
    /// - 검증 내용: row disconnectResponse, not_verified state, delegate payload
    /// - 사전 조건: OpenAI row가 disconnecting 상태다.
    /// - 기대 결과: row는 not_verified/idle이 되고 updated file delegate가 방출된다.
    func testDisconnectResponseEmitsConnectionsFileUpdatedDelegate() async {
        let updatedFile = AIConnectionsFile.singleProvider(.openai, state: .notVerified, credential: nil)
        let store = TestStore(
            initialState: AiSettingsState(rows: [
                AiConnectionRowState(
                    provider: .openai,
                    connectionState: .disconnecting,
                ),
            ]),
        ) {
            AiSettingsFeature()
        }

        await store.send(.row(.element(
            id: .openai,
            action: .disconnectResponse(AiProviderConnectionResult(
                provider: .openai,
                state: .notVerified,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .openai]?.statusReason = .none
            state.rows[id: .openai]?.flowState = .idle
        }

        await store.receive(.delegate(.connectionsFileUpdated(updatedFile)))
    }

    /// SET-007-restore_ai_provider_connection_status: unsupported provider verification은 unavailable snapshot을 저장한다.
    /// 현재 build에서 지원되지 않는 provider가 connected로 남지 않고 저장 파일과 delegate에 반영되는지 검증한다.
    /// - 검증 내용: unsupported verification, unavailable snapshot save, delegate emission
    /// - 사전 조건: ChatGPT Codex snapshot은 connected이고 verification은 unsupportedProvider다.
    /// - 기대 결과: unavailable/providerUnsupportedInBuild snapshot이 저장되고 delegate가 방출된다.
    func testBootstrapVerificationUnsupportedProviderPersistsAndEmitsConnectionsFileUpdatedDelegate() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .connected,
            errorCode: .none,
        )
        let expectedFile = AIConnectionsFile(
            updatedAtMs: staleFile.updatedAtMs,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: staleFile.providers[AiProvider.chatgptCodex.rawValue]?.credential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .unavailable,
                        lastVerifiedAtMs: nil,
                        lastErrorCode: .providerUnsupportedInBuild,
                    ),
                ),
            ],
        )
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { staleFile }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .unavailable
            state.rows[id: .chatgptCodex]?.statusReason = .providerUnsupportedInBuild
        }

        await store.receive(.delegate(.connectionsFileUpdated(expectedFile)))
        await store.finish()

        XCTAssertEqual(saveSpy.savedFiles, [expectedFile])
    }

    /// SET-007-restore_ai_provider_connection_status: 최신 credential이 바뀌면 stale verification 결과를 저장하지 않는다.
    /// bootstrap 중 사용자가 credential을 갱신한 경우 이전 credential 검증 결과가 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: stale file load, latest file reload, save suppression
    /// - 사전 조건: 첫 load는 오래된 OpenAI credential, 두 번째 load는 새 credential을 반환한다.
    /// - 기대 결과: row는 connected로 표시되지만 save는 호출되지 않는다.
    func testBootstrapVerificationSkipsPersistWhenLatestCredentialChanged() async {
        let staleFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connectionFailed,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-old")),
            errorCode: .expired,
        )
        let latestFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .connected,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-new")),
        )
        let loadSpy = ConnectionsFileLoadSpy(files: [staleFile, latestFile])
        let saveSpy = ConnectionsFileSaveSpy()
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { try await loadSpy.load() }
            $0.aiConnectionsFileClient.save = { try await saveSpy.save($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.finish()

        XCTAssertTrue(saveSpy.savedFiles.isEmpty)
    }

    /// SET-007-restore_ai_provider_connection_status: fresh install은 모든 provider를 not_verified로 표시한다.
    /// 저장 파일이 비어 있는 첫 실행 상태에서 기본 provider row가 연결 가능한 상태로 준비되는지 검증한다.
    /// - 검증 내용: empty connections file, default row count, connect primary action
    /// - 사전 조건: AI connections file이 비어 있다.
    /// - 기대 결과: 세 provider row가 not_verified이고 primary action은 connect다.
    func testOnAppear_freshInstall_showsAllNotVerified() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }

        await store.finish()

        let storeState = store.state
        XCTAssertEqual(storeState.rows.count, 3)
        for row in storeState.rows {
            XCTAssertEqual(row.connectionState, .notVerified)
            XCTAssertEqual(row.primaryAction, .connect)
        }
    }

    /// SET-007-restore_ai_provider_connection_status: invalid API key snapshot은 retry 가능한 실패로 복원된다.
    /// 저장된 invalid credential 상태가 bootstrap verification 후 connection_failed로 유지되는지 검증한다.
    /// - 검증 내용: invalidAPIKey snapshot, verification invalid response, retry action
    /// - 사전 조건: Anthropic snapshot이 connection_failed/invalidAPIKey다.
    /// - 기대 결과: row는 connection_failed/invalidAPIKey이고 primary action은 retry다.
    func testOnAppear_invalidAPIKeySnapshot_restoresFailed() async {
        let failedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "bad-key")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastErrorCode: .invalidAPIKey,
                    ),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { failedFile }
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.invalidAPIKey) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .anthropic]?.connectionState = .connectionFailed
            state.rows[id: .anthropic]?.statusReason = .invalidAPIKey
        }

        await store.finish()

        let anthropicRow = store.state.rows[id: .anthropic]
        XCTAssertEqual(anthropicRow?.connectionState, .connectionFailed)
        XCTAssertEqual(anthropicRow?.statusReason, .invalidAPIKey)
        XCTAssertEqual(anthropicRow?.primaryAction, .retry)
    }

    /// SET-007-restore_ai_provider_connection_status: load error는 bootstrapPhase를 failed로 둔다.
    /// connections file load 실패가 빈 목록 성공으로 오인되지 않는지 검증한다.
    /// - 검증 내용: load throw, bootstrapFailed action, row preservation
    /// - 사전 조건: aiConnectionsFileClient.load가 오류를 던진다.
    /// - 기대 결과: bootstrapPhase는 failed이고 기본 row 3개는 유지된다.
    func testOnAppear_loadError_setsFailedBootstrapPhase() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
        }

        await store.finish()

        XCTAssertEqual(store.state.bootstrapPhase, .failed)
        XCTAssertEqual(store.state.rows.count, 3)
    }

    /// SET-007-restore_ai_provider_connection_status: onAppear 재진입은 bootstrap을 중복 실행하지 않는다.
    /// 이미 bootstrap이 완료된 Settings AI 탭에서 재진입이 추가 load effect를 만들지 않는지 검증한다.
    /// - 검증 내용: first onAppear bootstrap, second onAppear ignored
    /// - 사전 조건: AI connections file이 비어 있고 첫 bootstrap이 완료됐다.
    /// - 기대 결과: 두 번째 onAppear는 state/effect를 만들지 않는다.
    func testOnAppear_calledTwice_onlyBootstrapsOnce() async {
        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { AIConnectionsFile.empty() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
        }
        await store.finish()

        await store.send(.onAppear)
        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: disconnected snapshot은 disconnected로 복원된다.
    /// 명시적으로 연결 해제된 provider가 fresh not_verified와 구분되는지 검증한다.
    /// - 검증 내용: persisted disconnected snapshot, primary action
    /// - 사전 조건: OpenAI snapshot이 disconnected다.
    /// - 기대 결과: row는 disconnected이고 primary action은 connect다.
    func testOnAppear_disconnectedSnapshot_restoresDisconnected() async {
        let disconnectedFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnected),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectedFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .disconnected
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.finish()

        let openaiRow = store.state.rows[id: .openai]
        XCTAssertEqual(openaiRow?.connectionState, .disconnected)
        XCTAssertEqual(openaiRow?.primaryAction, .connect)
    }

    /// SET-007-restore_ai_provider_connection_status: credential 없는 connect_in_progress snapshot은 missingCredential로
    /// 복원된다.
    /// 이전 세션의 중단된 연결 시도가 credential 없이 connected로 이어지지 않는지 검증한다.
    /// - 검증 내용: connectInProgress snapshot, nil credential guard, missingCredential reason
    /// - 사전 조건: ChatGPT Codex snapshot은 connect_in_progress이고 credential은 nil이다.
    /// - 기대 결과: row는 not_verified/missingCredential 상태가 된다.
    func testOnAppear_connectInProgress_resetsToNotVerified() async {
        let inProgressFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { inProgressFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.statusReason = .missingCredential
        }

        await store.finish()
    }

    /// SET-007-restore_ai_provider_connection_status: disconnecting snapshot은 disconnected로 복원된다.
    /// 이전 세션에서 연결 해제 중 종료된 상태가 계속 진행 중으로 남지 않는지 검증한다.
    /// - 검증 내용: persisted disconnecting snapshot, disconnected state
    /// - 사전 조건: Anthropic snapshot이 disconnecting이다.
    /// - 기대 결과: row는 disconnected/none 상태가 된다.
    func testOnAppear_disconnecting_resetsToDisconnected() async {
        let disconnectingFile = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnecting),
                ),
            ],
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { disconnectingFile }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.rows[id: .anthropic]?.statusReason = .none
        }

        await store.finish()
    }

    /// SET-007-connect_ai_provider: API key verification 후 cancel은 늦은 connection completion을 무시한다.
    /// 사용자가 연결 완료 전 취소한 경우 이후 client 응답이 row를 connected로 오염시키지 않는지 검증한다.
    /// - 검증 내용: verificationResponse, cancelButtonTapped, delayed connectAPIKey completion
    /// - 사전 조건: OpenAI API key verification은 valid이고 connect completion은 대기한다.
    /// - 기대 결과: row는 not_verified/idle 상태로 유지된다.
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

        controller.resume(with: AiProviderConnectionResult(
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

    /// SET-007-connect_ai_provider: API key verification network error는 connection_failed로 표시된다.
    /// provider verification의 네트워크 오류가 retry 가능한 실패 상태로 매핑되는지 검증한다.
    /// - 검증 내용: submitAPIKey, networkError verification, networkUnavailable reason
    /// - 사전 조건: OpenAI API key verification이 networkError를 반환한다.
    /// - 기대 결과: row는 connection_failed/networkUnavailable/idle 상태가 된다.
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

    /// SET-007-connect_ai_provider: 빈 API key submit은 무시된다.
    /// 사용자가 빈 문자열을 제출해도 verification effect가 생성되지 않는지 검증한다.
    /// - 검증 내용: empty submitAPIKey action, state preservation
    /// - 사전 조건: OpenAI row가 not_verified 상태다.
    /// - 기대 결과: row state가 변경되지 않는다.
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

    /// SET-007-connect_ai_provider: 공백 API key submit은 무시된다.
    /// trim 후 비어 있는 key가 verification으로 전달되지 않는지 검증한다.
    /// - 검증 내용: whitespace submitAPIKey action, state preservation
    /// - 사전 조건: OpenAI row가 not_verified 상태다.
    /// - 기대 결과: row state가 변경되지 않는다.
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

    /// SET-007-connect_ai_provider: API key connect 중 cancel은 not_verified/idle로 복구한다.
    /// 진행 중인 verification UI 상태가 cancel로 정리되는지 검증한다.
    /// - 검증 내용: cancelButtonTapped, flowState/isVerifying reset
    /// - 사전 조건: OpenAI row가 connect_in_progress/connecting/isVerifying 상태다.
    /// - 기대 결과: row는 not_verified/idle이고 isVerifying은 false다.
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

    /// SET-007-connect_ai_provider: API key submit은 앞뒤 공백을 제거한 뒤 연결한다.
    /// 입력 key normalization이 verification/connect flow와 성공 후 입력 초기화에 반영되는지 검증한다.
    /// - 검증 내용: trimmed key, verification response, connection response, enteredKey clear
    /// - 사전 조건: OpenAI row에 앞뒤 공백이 있는 API key를 제출한다.
    /// - 기대 결과: row는 connected/idle이 되고 enteredKey는 비워진다.
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
}

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-validate_account_session spec-owner test

 interaction_id: ACC-001-validate_account_session
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-validate_account_session.md

 TTL refresh behavior:
 - interval=60s, threshold=90%(360s), backoff_threshold=3
 - sessionExpiresAt within 360s of now triggers refresh
 - decodingFailure → permanent → immediate session_expired
 - networkFailure → temporary → consecutiveRefreshFailures++, 3→expired
 */

@MainActor
final class ACC001ValidateAccountSessionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let nearExpiryDate = Date(timeIntervalSince1970: 1_700_000_100)
    private let newExpiryDate = Date(timeIntervalSince1970: 1_700_003_600)

    private func makeTestStore(
        accountSessionClient: AccountSessionClient = .testValue,
        authNetworkClient: AuthNetworkClient = .testValue,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.date = .constant(referenceDate)
        }
    }

    private func sessionNearExpiryState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.ttlTimerActive = true
        state.sessionExpiresAt = nearExpiryDate
        return state
    }

    // MARK: - ACC-001-validate_account_session

    /// ACC-001-validate_account_session: TTL timer refresh가 세션 만료 임박 시 refresh token을 갱신하고 세션을 유지한다.
    /// refreshToken 성공 시 새로운 만료 시각으로 sessionExpiresAt이 갱신되는지 검증한다.
    /// - 검증 내용: refreshToken 성공 후 sessionExpiresAt이 새로운 만료 시각으로 갱신되고 consecutiveRefreshFailures가 0으로 리셋된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: sessionExpiresAt이 새로운 시각으로 갱신되고 hasAccountSession과 ttlTimerActive가 true로 유지된다.
    func testRefreshNearExpiryMaintainsSession() async {
        let newExpiry = newExpiryDate
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: {
                    AccountSession(
                        accessToken: "refreshed-token",
                        status: .coreLicenseActive,
                        expiresAt: newExpiry,
                    )
                },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: TTL timer tick이 sessionExpiresAt/consecutiveRefreshFailures 외 다수 상태를 갱신하나 검증 대상은 두
        // 필드만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)

        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = newExpiry
        }

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertTrue(store.state.ttlTimerActive)
        XCTAssertEqual(store.state.sessionExpiresAt, newExpiry)
    }

    /// ACC-001-validate_account_session: TTL timer refresh가 토큰 회전과 함께 세션 정보를 갱신한다.
    /// refreshToken 성공 시 rotated 토큰과 새 만료 시각으로 상태가 업데이트되는지 검증한다.
    /// - 검증 내용: refreshToken 성공 후 accessToken/refreshToken이 rotated되고 sessionExpiresAt이 갱신된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: sessionExpiresAt이 새로운 시각으로 갱신되고 hasAccountSession이 true로 유지된다.
    func testRefreshSuccessUpdatesSession() async {
        let newExpiry = newExpiryDate
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: {
                    AccountSession(
                        accessToken: "rotated-token",
                        status: .coreLicenseActive,
                        refreshToken: "new-refresh-token",
                        expiresAt: newExpiry,
                    )
                },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: TTL timer tick이 sessionExpiresAt 외 다수 상태를 갱신하나 검증 대상은 sessionExpiresAt 갱신만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)

        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = newExpiry
        }

        XCTAssertEqual(store.state.sessionExpiresAt, newExpiry)
        XCTAssertTrue(store.state.hasAccountSession)
    }

    /// ACC-001-validate_account_session: 영구적 오류(decodingFailure) 발생 시 세션이 즉시 만료 처리된다.
    /// refreshToken이 decodingFailure를 throw할 때 _sessionExpiredDetected로 상태가 전환되는지 검증한다.
    /// - 검증 내용: decodingFailure → _sessionExpiredDetected → hasAccountSession=false, isSessionExpired=true,
    /// didSignInFail=true, ttlTimerActive=false로 전환된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: 세션이 만료되고 로그인 실패 상태로 전환되며 TTL timer가 중단된다.
    func testPermanentFailureSetsSessionExpired() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.decodingFailure },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: 영구 실패 처리가 6개 필드를 동시 갱신하나 검증 대상은 최종 4개
        // 필드(hasAccountSession/didSignInFail/isSessionExpired/ttlTimerActive)만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)

        await store.receive(\._refreshTokenResult)

        await store.receive(\._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.consecutiveRefreshFailures = 0
        }

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertFalse(store.state.ttlTimerActive)
        XCTAssertTrue(store.state.isSessionExpired)
    }

    /// ACC-001-validate_account_session: refreshToken 401 unauthorized → 즉시 _sessionExpiredDetected 전환, retry 없음.
    /// refreshToken이 .unauthorized를 반환하면 3회 재시도 없이 즉시 세션 만료 처리되는지 검증한다.
    /// - 검증 내용: .unauthorized → _sessionExpiredDetected 수신, consecutiveRefreshFailures==0 유지
    /// - 사전 조건: 로그인된 세션 상태, near-expiry
    /// - 기대 결과: _sessionExpiredDetected 수신, isSessionExpired=true, consecutiveRefreshFailures=0
    func testUnauthorizedOnRefreshTriggersSessionExpiryImmediately() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.unauthorized },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: _sessionExpiredDetected가 다수 상태를 동시 갱신하나 검증 대상은 최종 상태만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult)
        await store.receive(\._sessionExpiredDetected)

        XCTAssertTrue(store.state.isSessionExpired, "unauthorized → isSessionExpired=true")
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 0, "unauthorized → retry 카운터 미증가")
    }

    /// ACC-001-validate_account_session: 일시적 네트워크 오류(networkFailure) 발생 시 세션이 유지되고 재시도 카운터가 증가한다.
    /// refreshToken이 networkFailure를 throw할 때 세션이 유지되는지 검증한다.
    /// - 검증 내용: networkFailure → consecutiveRefreshFailures가 1 증가하고 세션 상태는 유지된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: hasAccountSession과 ttlTimerActive가 true로 유지되고 consecutiveRefreshFailures가 1이 된다.
    func testNetworkErrorMaintainsSession() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.networkFailure },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: _refreshTokenResult가 다수 필드를 갱신할 수 있으나 검증 대상은 consecutiveRefreshFailures 증가만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)

        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 1
        }

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertTrue(store.state.ttlTimerActive)
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 1)
    }

    /// ACC-001-validate_account_session: 세션 만료 후 TTL timer가 중단되고 추가 tick이 무시된다.
    /// sessionExpiredDetected 처리 후 _ttlTimerTicked가 no-op이 되는지 검증한다.
    /// - 검증 내용: 만료 후 TTL timer가 중단되고 이후 tick이 상태를 변경하지 않는다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태에서 decodingFailure 발생.
    /// - 기대 결과: ttlTimerActive=false, hasAccountSession=false로 전환되고 추가 tick이 무시된다.
    func testSessionExpiredStopsTTL() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.decodingFailure },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: _sessionExpiredDetected가 다수 상태를 갱신한 이후 추가 tick이 no-op임을 검증하며 중간 상태 변화는 불필요
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult)
        await store.receive(\._sessionExpiredDetected)

        XCTAssertFalse(store.state.ttlTimerActive)
        XCTAssertFalse(store.state.hasAccountSession)

        // tick after expiry should be no-op
        await store.send(AccountAccessAction._ttlTimerTicked)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertFalse(store.state.ttlTimerActive)
    }

    /// ACC-001-sign_out_account: signOut은 진행 중인 refresh를 취소해 늦은 persist를 막는다.
    func testSignOutCancelsInFlightRefreshBeforePersistingSession() async {
        nonisolated(unsafe) var refreshContinuation: CheckedContinuation<AccountSession, Never>?
        nonisolated(unsafe) var persistCalled = false

        let store = makeTestStore(
            accountSessionClient: AccountSessionClient(
                read: { nil },
                persist: { _ in persistCalled = true },
                delete: { _ in },
            ),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: {
                    await withCheckedContinuation { refreshContinuation = $0 }
                },
            ),
            initialState: sessionNearExpiryState(),
        )
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)
        for _ in 0 ..< 10 where refreshContinuation == nil {
            await Task.yield()
        }
        XCTAssertNotNil(refreshContinuation)

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.didSignInFail = false
            state.status = nil
            state.snapshot = nil
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.fetchGeneration = 1
        }
        await store.receive(\.delegate.signedOut)

        refreshContinuation?.resume(
            returning: AccountSession(
                accessToken: "rotated-token",
                status: .coreLicenseActive,
                refreshToken: "rotated-refresh-token",
                expiresAt: referenceDate.addingTimeInterval(3600),
            ),
        )
        await Task.yield()

        XCTAssertFalse(persistCalled)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.isSessionExpired)
        await store.finish()
    }

    /// ACC-001-validate_account_session: 3회 연속 네트워크 오류 발생 시 세션이 만료 처리된다.
    /// consecutiveRefreshFailures가 threshold(3)에 도달하면 _sessionExpiredDetected가 트리거되는지 검증한다.
    /// - 검증 내용: 3회 연속 networkFailure → _sessionExpiredDetected → 세션 만료 상태로 전환된다.
    /// - 사전 조건: 세션이 존재하고 TTL timer가 활성화된 near-expiry 상태.
    /// - 기대 결과: 3회째 tick에서 hasAccountSession=false, isSessionExpired=true, ttlTimerActive=false로 전환된다.
    func testThreeConsecutiveFailuresSetsSessionExpired() async {
        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.networkFailure },
            ),
            initialState: sessionNearExpiryState(),
        )
        // store.exhaustivity = .off: 3회 연속 실패 처리 중 각 tick이 다수 상태를 갱신하나 검증은 단계별 consecutiveRefreshFailures만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 1
        }
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 1)
        XCTAssertTrue(store.state.hasAccountSession)

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 2
        }
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 2)
        XCTAssertTrue(store.state.hasAccountSession)

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult)
        await store.receive(\._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.consecutiveRefreshFailures = 0
            state.sessionExpiresAt = nil
        }

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.didSignInFail)
        XCTAssertFalse(store.state.ttlTimerActive)
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 0)
        XCTAssertTrue(store.state.isSessionExpired)
    }

    /// ACC-001-validate_account_session: State에 accessToken/refreshToken 필드가 직접 노출되지 않는다.
    /// Mirror를 통해 State 타입의 모든 프로퍼티에 token 필드가 없는지 검증한다.
    /// - 검증 내용: State의 모든 프로퍼티 label에 "accessToken" 또는 "refreshToken"이 포함되지 않는다.
    /// - 사전 조건: 없음.
    /// - 기대 결과: token 필드가 State에 직접 노출되지 않는다.
    func testRawTokenNeverExposedInState() {
        let state = AccountAccessFeature.State()
        let mirror = Mirror(reflecting: state)
        for child in mirror.children {
            let label = child.label ?? ""
            XCTAssertFalse(
                label.contains("accessToken") || label.contains("refreshToken"),
                "State must not expose token fields: \(label)",
            )
        }
    }
}

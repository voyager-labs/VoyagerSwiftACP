// swiftlint:disable force_unwrapping

@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

/*
 ACC-001-detect_session_expiry spec-owner 테스트

 interaction_id: ACC-001-detect_session_expiry
 spec: docs/canonical/PRODUCT/05_FEATURE_SPECS/acc/ACC-001-manage_account_auth/ACC-001-detect_session_expiry.md

 session 만료 감지 → _sessionExpiredDetected 단일 진입점을 통한 상태 전환 검증.
 dedup guard로 중복 만료 처리를 방지한다.
 */

@MainActor
final class ACC001DetectSessionExpiryTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        accountAccessClient: AccountAccessClient = .mock,
        initialState: AccountAccessFeature.State = AccountAccessFeature.State(),
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: initialState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountAccessClient = accountAccessClient
            $0.date = .constant(referenceDate)
        }
    }

    private func signedInState() -> AccountAccessFeature.State {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.ttlTimerActive = true
        state.sessionExpiresAt = Date(timeIntervalSince1970: 1_700_000_100)
        return state
    }

    // MARK: - ACC-001-detect_session_expiry

    /// ACC-001-detect_session_expiry: 영구적 refresh 실패 시 세션 만료 상태로 전환된다.
    /// decodingFailure 발생 시 _sessionExpiredDetected action을 통해 상태가 올바르게 전환되는지 검증한다.
    /// - 검증 내용: decodingFailure → _sessionExpiredDetected → didSignInFail=true, isSessionExpired=true,
    /// accountAccessAuthAxis==.signInFailed로 전환된다.
    /// - 사전 조건: 로그인된 세션 상태.
    /// - 기대 결과: didSignInFail=true, isSessionExpired=true, accountAccessAuthAxis==.signInFailed.
    func testPermanentFailureTransitionsToSessionExpired() async {
        let mockClient = AccountAccessClient(
            restoreSession: { nil },
            fetchAccessStatus: { throw AccessError.notConfigured },
            signOut: {},
            exchangeAppHandoff: { _, _, _ in throw AccessError.notConfigured },
            refreshToken: { throw AccessError.decodingFailure },
        )
        let store = makeTestStore(
            accountAccessClient: mockClient,
            initialState: signedInState(),
        )
        // store.exhaustivity = .off: _sessionExpiredDetected가 다수 상태를 동시 갱신하나 검증 대상은
        // didSignInFail/isSessionExpired/accountAccessAuthAxis만 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)
        await store.receive(\._refreshTokenResult)
        await store.receive(\._sessionExpiredDetected)

        XCTAssertTrue(store.state.didSignInFail, "영구 실패 → didSignInFail=true")
        XCTAssertTrue(store.state.isSessionExpired, "영구 실패 → isSessionExpired=true")
        XCTAssertEqual(store.state.accountAccessAuthAxis, .signInFailed, "auth_state → signInFailed")
    }

    /// ACC-001-detect_session_expiry: 세션 만료 시 guard 표시 조건이 올바르게 설정된다.
    /// session_expired 상태에서 guard surface 표시 조건을 검증한다.
    /// - 검증 내용: session_expired 상태에서 accountAccessAuthAxis==.signInFailed, canStartLogin==true가 된다.
    /// - 사전 조건: didSignInFail=true, isSessionExpired=true 상태.
    /// - 기대 결과: accountAccessAuthAxis==.signInFailed, canStartLogin==true.
    func testSessionExpiredShowsGuardSurface() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.didSignInFail = true
        state.isSessionExpired = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(state.canStartLogin, "session_expired → Login CTA 활성화 (ACC-003 guard)")
    }

    /// ACC-001-detect_session_expiry: 세션 만료 시 세션 정보가 무효화된다.
    /// _sessionExpiredDetected 처리 후 세션 관련 상태가 초기화되는지 검증한다.
    /// - 검증 내용: hasAccountSession=false, ttlTimerActive=false, sessionExpiresAt=nil, consecutiveRefreshFailures=0으로
    /// 설정된다.
    /// - 사전 조건: 로그인된 세션 상태.
    /// - 기대 결과: 세션이 무효화되고 TTL timer가 중단되며 만료 시각이 초기화된다.
    func testSessionExpiredInvalidatesSession() async {
        let initialState = signedInState()
        let store = makeTestStore(initialState: initialState)

        await store.send(AccountAccessAction._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.consecutiveRefreshFailures = 0
        }

        XCTAssertFalse(store.state.hasAccountSession, "세션 무효화")
        XCTAssertFalse(store.state.ttlTimerActive, "TTL 타이머 중단")
        XCTAssertNil(store.state.sessionExpiresAt, "만료 시각 초기화")
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 0, "연속 실패 카운터 리셋")
    }

    /// ACC-001-detect_session_expiry: 세션 만료 시 ACC-002 entitlement 재평가가 트리거된다.
    /// session_expired 상태에서 requiresAccountSession이 true가 되는지 검증한다.
    /// - 검증 내용: _sessionExpiredDetected 처리 후 requiresAccountSession==true가 된다.
    /// - 사전 조건: 로그인된 세션 상태.
    /// - 기대 결과: requiresAccountSession==true로 설정되어 ACC-002 재평가가 가능해진다.
    func testSessionExpiredTriggersEntitlementReevaluation() async {
        let initialState = signedInState()
        let store = makeTestStore(initialState: initialState)

        await store.send(AccountAccessAction._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.consecutiveRefreshFailures = 0
        }

        XCTAssertTrue(store.state.requiresAccountSession, "ACC-002 재평가 트리거: requiresAccountSession=true")
    }

    /// ACC-001-detect_session_expiry: 중복 만료 처리가 dedup guard에 의해 무시된다.
    /// _sessionExpiredDetected가 두 번 전송되어도 두 번째가 no-op인지 검증한다.
    /// - 검증 내용: 두 번째 _sessionExpiredDetected 전송 후 isSessionExpired와 hasAccountSession이 첫 번째와 동일하게 유지된다.
    /// - 사전 조건: 처음 _sessionExpiredDetected가 전송된 상태.
    /// - 기대 결과: 두 번째 전송이 무시되고 모든 상태가 유지된다.
    func testDedupGuardIgnoresDuplicateExpiry() async {
        let store = makeTestStore()

        // 첫 번째 _sessionExpiredDetected
        await store.send(AccountAccessAction._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
        }

        let afterFirst = store.state.isSessionExpired
        let hasSessionAfterFirst = store.state.hasAccountSession

        // 두 번째 _sessionExpiredDetected → dedup guard 작동, state 유지
        await store.send(AccountAccessAction._sessionExpiredDetected)

        XCTAssertEqual(store.state.isSessionExpired, afterFirst, "두 번째 전송 후 isSessionExpired 유지")
        XCTAssertEqual(store.state.hasAccountSession, hasSessionAfterFirst, "두 번째 전송 후 hasAccountSession 유지")
        XCTAssertTrue(store.state.didSignInFail, "didSignInFail 유지")
    }

    /// ACC-001-detect_session_expiry: 네트워크 오류 시 세션 만료가 트리거되지 않는다.
    /// networkFailure 발생 시 _sessionExpiredDetected가 전송되지 않고 세션이 유지되는지 검증한다.
    /// - 검증 내용: networkFailure → consecutiveRefreshFailures 증가, _sessionExpiredDetected 미전송, 세션 상태 유지.
    /// - 사전 조건: 로그인된 세션 상태.
    /// - 기대 결과: hasAccountSession=true, isSessionExpired=false, ttlTimerActive=true, consecutiveRefreshFailures=1.
    func testNetworkErrorDoesNotTriggerSessionExpiry() async {
        let mockClient = AccountAccessClient(
            restoreSession: { nil },
            fetchAccessStatus: { throw AccessError.notConfigured },
            signOut: {},
            exchangeAppHandoff: { _, _, _ in throw AccessError.notConfigured },
            refreshToken: { throw AccessError.networkFailure },
        )
        let store = makeTestStore(
            accountAccessClient: mockClient,
            initialState: signedInState(),
        )
        // store.exhaustivity = .off: networkFailure 처리가 다수 상태를 갱신할 수 있으나 검증 대상은 consecutiveRefreshFailures 증가와 세션 유지만
        // 해당
        store.exhaustivity = .off

        await store.send(AccountAccessAction._ttlTimerTicked)

        await store.receive(\._refreshTokenResult) { state in
            state.consecutiveRefreshFailures = 1
        }

        // _sessionExpiredDetected가 전송되지 않아야 함
        XCTAssertTrue(store.state.hasAccountSession, "네트워크 오류 → 세션 유지")
        XCTAssertFalse(store.state.isSessionExpired, "네트워크 오류 → 만료 미감지")
        XCTAssertTrue(store.state.ttlTimerActive, "네트워크 오류 → TTL 타이머 지속")
        XCTAssertEqual(store.state.consecutiveRefreshFailures, 1, "연속 실패 카운터 증가")
    }

    /// ACC-001-detect_session_expiry: 복수 경로를 통한 중복 만료 처리가 방지된다.
    /// 동일한 _sessionExpiredDetected가 재전송되어도 dedup guard가 동작하는지 검증한다.
    /// - 검증 내용: 중복 _sessionExpiredDetected 전송 후 isSessionExpired와 hasAccountSession이 첫 번째 이후와 동일하게 유지된다.
    /// - 사전 조건: 처음 _sessionExpiredDetected가 전송되어 isSessionExpired=true가 된 상태.
    /// - 기대 결과: 두 번째 전송이 무시되고 isSessionExpired=true, hasAccountSession=false, didSignInFail=true가 유지된다.
    func testMultipleExpiryPathsDedupPreventsDuplicateProcessing() async {
        let store = makeTestStore(initialState: signedInState())

        // 경로 1: 직접 _sessionExpiredDetected 전송
        await store.send(AccountAccessAction._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.didSignInFail = true
            state.isSessionExpired = true
            state.ttlTimerActive = false
            state.sessionExpiresAt = nil
            state.consecutiveRefreshFailures = 0
        }

        XCTAssertTrue(store.state.isSessionExpired)
        XCTAssertFalse(store.state.hasAccountSession)

        // 경로 2: 이미 만료 상태에서 동일한 만료 action 재전송 → 무시
        await store.send(AccountAccessAction._sessionExpiredDetected)

        // state가 첫 번째 전송 이후와 동일하게 유지
        XCTAssertTrue(store.state.isSessionExpired)
        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertTrue(store.state.didSignInFail)
    }
}

// swiftlint:enable force_unwrapping

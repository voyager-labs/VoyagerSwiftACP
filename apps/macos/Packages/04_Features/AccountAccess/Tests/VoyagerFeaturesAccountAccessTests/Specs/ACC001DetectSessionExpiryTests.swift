import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001DetectSessionExpiryTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = UUID()
        return TestStore(initialState: state) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
            $0.continuousClock = TestClock()
        }
    }

    // MARK: - ACC-001-detect_session_expiry

    /// ACC-001-detect_session_expiry: 세션 만료 감지는 세션 상태를 signed-out으로 전환한다.
    /// 만료 action이 재로그인 가능한 상태를 만드는지 검증한다.
    /// - 검증 내용: session flags, expiry metadata, retry state 초기화
    /// - 사전 조건: 유효한 account session
    /// - 기대 결과: hasAccountSession=false, isSessionExpired=true, didSignInFail=true
    func testSessionExpiryClearsSessionState() async {
        let store = makeStore()
        await store.send(._sessionExpiredDetected) { state in
            state.hasAccountSession = false
            state.isSessionExpired = true
            state.didSignInFail = true
            state.sessionExpiresAt = nil
            state.sessionBindingID = nil
            state.ttlTimerActive = false
            state.fetchGeneration = 1
            state.syncGeneration = 1
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.finish()
    }

    /// ACC-001-detect_session_expiry: 중복 만료 감지는 한 번만 상태를 전환한다.
    /// dedup guard가 이미 만료된 session을 다시 변경하지 않는지 검증한다.
    /// - 검증 내용: 두 번째 _sessionExpiredDetected가 no-op
    /// - 사전 조건: isSessionExpired=true 상태
    /// - 기대 결과: 동일한 session expiry 상태 유지
    func testRepeatedSessionExpiryIsIgnored() async {
        var state = AccountAccessFeature.State()
        state.isSessionExpired = true
        state.didSignInFail = true
        let store = TestStore(initialState: state) { AccountAccessFeature() }
        await store.send(._sessionExpiredDetected)
        XCTAssertTrue(store.state.isSessionExpired)
    }
}

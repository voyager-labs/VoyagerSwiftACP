import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001CompleteAuthHandoffCallbackTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(session: AccountSession? = nil)
        -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action>
    {
        TestStore(initialState: AccountAccessFeature.State()) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
            $0.continuousClock = TestClock()
        }
    }

    // MARK: - ACC-001-complete_auth_handoff_callback

    /// ACC-001-complete_auth_handoff_callback: 인증 callback URL은 저장된 세션 복원 경로로 연결된다.
    /// query가 없는 인증 callback을 처리할 때 session client를 읽는지 검증한다.
    /// - 검증 내용: loginCallbackReceived 후 _loginSessionRestored가 전송됨
    /// - 사전 조건: 유효한 voyager://auth/callback URL과 저장된 AccountSession
    /// - 기대 결과: 세션이 복원되고 refresh deadline이 활성화됨
    func testCallbackRestoresPersistedSession() async throws {
        let expiresAt = referenceDate.addingTimeInterval(3600)
        let session = AccountSession(accessToken: "access", status: .coreLicenseActive, expiresAt: expiresAt)
        let store = makeStore(session: session)

        try await store.send(.loginCallbackReceived(XCTUnwrap(URL(string: "voyager://auth/callback"))))
        await store.receive(\._loginSessionRestored) { state in
            state.hasAccountSession = true
            state.isSessionExpired = false
            state.sessionExpiresAt = expiresAt
            state.sessionBindingID = session.sessionBindingID
            state.ttlTimerActive = true
            state.fetchGeneration = 1
            state.syncGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.skipReceivedActions()
        await store.skipInFlightEffects()
    }

    /// ACC-001-complete_auth_handoff_callback: 잘못된 callback은 세션 상태를 바꾸지 않는다.
    /// callback scheme, host, path가 맞지 않으면 아무 effect도 만들지 않는지 검증한다.
    /// - 검증 내용: invalid callback 전후 State 동일
    /// - 사전 조건: 다른 scheme의 callback URL
    /// - 기대 결과: hasAccountSession=false 유지
    func testInvalidCallbackIsIgnored() async throws {
        let store = makeStore()
        try await store.send(.loginCallbackReceived(XCTUnwrap(URL(string: "https://auth/callback"))))
        XCTAssertFalse(store.state.hasAccountSession)
    }
}

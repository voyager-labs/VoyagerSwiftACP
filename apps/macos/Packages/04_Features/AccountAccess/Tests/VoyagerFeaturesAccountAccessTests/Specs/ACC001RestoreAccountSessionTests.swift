import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001RestoreAccountSessionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(initialState: AccountAccessFeature
        .State = .init()) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action>
    {
        TestStore(initialState: initialState) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
            $0.continuousClock = TestClock()
        }
    }

    // MARK: - ACC-001-restore_account_session

    /// ACC-001-restore_account_session: persisted session이 있으면 signed-in 상태로 복원한다.
    /// launch restoration action이 session metadata를 state에 반영하는지 검증한다.
    /// - 검증 내용: account session, expiry, binding, timer 상태
    /// - 사전 조건: 미래 expiry를 가진 AccountSession
    /// - 기대 결과: hasAccountSession=true와 session metadata 보존
    func testAvailableSessionIsRestored() async {
        let expiresAt = referenceDate.addingTimeInterval(3600)
        let session = AccountSession(accessToken: "access", status: .coreLicenseActive, expiresAt: expiresAt)
        let store = makeStore()

        await store.send(._onAppearSessionRestored(.available(session: session))) { state in
            state.hasAccountSession = true
            state.sessionExpiresAt = expiresAt
            state.sessionBindingID = session.sessionBindingID
            state.ttlTimerActive = true
            state.refreshDeadlineGeneration = 1
        }
        await store.skipReceivedActions()
        await store.skipInFlightEffects()
    }

    /// ACC-001-restore_account_session: persisted session이 없으면 signed-out 상태로 남는다.
    /// missing restoration이 stale session metadata를 제거하는지 검증한다.
    /// - 검증 내용: session flags와 expiry metadata 초기화
    /// - 사전 조건: stale session metadata가 있는 initial state
    /// - 기대 결과: hasAccountSession=false, sessionExpiresAt=nil
    func testMissingSessionClearsStaleMetadata() async {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = UUID()
        let store = makeStore(initialState: state)

        await store.send(._onAppearSessionRestored(.missing)) { state in
            state.hasAccountSession = false
            state.sessionExpiresAt = nil
            state.sessionBindingID = nil
            state.ttlTimerActive = false
            state.fetchGeneration = 1
            state.refreshDeadlineGeneration = 1
            state.syncGeneration = 1
        }
        await store.finish()
    }
}

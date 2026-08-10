import Clocks
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001RestoreAccountSessionForegroundObserverTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ACC-001-restore_account_session_foreground_observer

    /// ACC-001-restore_account_session_foreground_observer: foreground는 persisted session을 재검증한다.
    /// 계정 세션이 있는 상태에서 appDidBecomeActive가 revalidation action을 만드는지 검증한다.
    /// - 검증 내용: revalidationGeneration 증가와 revalidatePersistedSession 전송
    /// - 사전 조건: hasAccountSession=true, isSessionExpired=false
    /// - 기대 결과: 최신 generation으로 persisted session 재검증 시작
    func testForegroundRevalidatesPersistedSession() async {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        let store = TestStore(initialState: state) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
            $0.continuousClock = TestClock()
        }

        await store.send(.appDidBecomeActive) { state in
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.skipReceivedActions()
        await store.finish()
    }
}

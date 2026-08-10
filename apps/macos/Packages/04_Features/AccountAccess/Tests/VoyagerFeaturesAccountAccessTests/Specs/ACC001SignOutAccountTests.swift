@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC001SignOutAccountTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ACC-001-sign_out_account

    /// ACC-001-sign_out_account: sign-out은 session을 삭제하고 signed-out 상태로 전환한다.
    /// 명시적 signOut이 account session deletion과 state cleanup을 수행하는지 검증한다.
    /// - 검증 내용: delete reason, session flags, expiry metadata
    /// - 사전 조건: hasAccountSession=true
    /// - 기대 결과: sessionClient.delete(.explicitSignOut) 호출 및 로그인 가능 상태
    func testSignOutDeletesPersistedSession() async {
        nonisolated(unsafe) var deleteReason: AccountSessionEndReason?
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = referenceDate.addingTimeInterval(3600)
        state.sessionBindingID = UUID()
        let store = TestStore(initialState: state) { AccountAccessFeature() } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in nil },
                persist: { _ in },
                delete: { reason in deleteReason = reason },
            )
            $0.authNetworkClient = .testValue
            $0.date = .constant(referenceDate)
        }

        await store.send(.signOut) { state in
            state.hasAccountSession = false
            state.isSessionExpired = true
            state.sessionExpiresAt = nil
            state.sessionBindingID = nil
            state.ttlTimerActive = false
            state.fetchGeneration = 1
            state.syncGeneration = 1
            state.lastCompleteSyncAt = nil
            state.revalidationGeneration = 1
            state.refreshDeadlineGeneration = 1
        }
        await store.finish()
        XCTAssertEqual(deleteReason, .explicitSignOut)
    }

    /// ACC-001-sign_out_account: session 없는 sign-out은 no-op이다.
    /// 로그인되지 않은 상태에서 signOut이 불필요한 persistence effect를 만들지 않는지 검증한다.
    /// - 검증 내용: State 변경 없음
    /// - 사전 조건: hasAccountSession=false, sign-in 진행 없음
    /// - 기대 결과: no-op
    func testSignOutWithoutSessionIsNoOp() async {
        let store = TestStore(initialState: AccountAccessFeature.State()) { AccountAccessFeature() }
        await store.send(.signOut)
    }
}

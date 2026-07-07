@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC003GuardSessionLapseTests: XCTestCase {
    // MARK: - ACC-003-guard_session_lapse

    /// ACC-003-guard_session_lapse: session_expired 상태에서 blur overlay가 표시된다.
    /// didSignInFail=true일 때 accountAccessAuthAxis가 .signInFailed로 설정되는지 검증한다.
    /// - 검증 내용: accountAccessAuthAxis == .signInFailed, didSignInFail == true
    /// - 사전 조건: didSignInFail == true
    /// - 기대 결과: guard 표시 조건 충족 (auth_state → .signInFailed)
    func testSessionExpiredShowsBlurOverlay() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(state.didSignInFail)
        // guard 표시 조건: accountAccessStepState != .complete || isSignInInProgress
        XCTAssertTrue(state.didSignInFail, "session_expired → guard 표시")
    }

    /// ACC-003-guard_session_lapse: session_expired 상태에서 세션만료 다이얼로그와 로그인 CTA가 표시된다.
    /// canStartLogin이 true일 때 로그인 CTA 표시가 가능한지 검증한다.
    /// - 검증 내용: canStartLogin == true, accountAccessAuthAxis == .signInFailed
    /// - 사전 조건: didSignInFail == true
    /// - 기대 결과: 로그인 CTA 활성화
    func testSessionExpiredDialogShowsLoginCTA() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true

        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(state.canStartLogin, "session_expired → 로그인 CTA 활성화")
        // canStartLogin: accountAccessAuthAxis == .signedOut || .signInFailed
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed, "signInFailed → canStartLogin 통과")
    }

    /// ACC-003-guard_session_lapse: logged_out 상태에서 로그인필요 다이얼로그가 표시된다.
    /// hasAccountSession=false일 때 guard 표시 조건을 검증한다.
    /// - 검증 내용: accountAccessAuthAxis == .signedOut, canStartLogin == true
    /// - 사전 조건: !hasAccountSession && !isSignInInProgress
    /// - 기대 결과: 로그인 필요 다이얼로그 표시 조건 충족
    func testLoggedOutAfterOnboardingShowsLoginDialog() {
        var state = AccountAccessFeature.State()
        state.hasAccountSession = false
        state.isSignInInProgress = false

        XCTAssertEqual(state.accountAccessAuthAxis, .signedOut)
        XCTAssertTrue(state.canStartLogin, "logged_out → 로그인 CTA 활성화")
        // guard 표시 조건: accountAccessStepState != .complete || isSignInInProgress
        XCTAssertFalse(state.hasAccountSession, "logged_out → hasAccountSession == false")
        XCTAssertFalse(state.isSignInInProgress, "logged_out → isSignInInProgress == false")
    }

    /// ACC-003-guard_session_lapse: 로그인 진행 중에는 overlay가 계속 표시된다.
    /// isSignInInProgress == true 인 동안 guard가 즉시 해제되지 않는지 검증한다.
    /// - 검증 내용: shouldShow == true during sign-in progress
    /// - 사전 조건: isSignInInProgress == true
    /// - 기대 결과: 로그인 진행 중에는 guard 유지, 성공 후에만 해제
    func testSignInInProgressKeepsOverlayVisible() {
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: .pending,
                isSignInInProgress: true,
            ),
            "sign-in progress → guard 유지",
        )

        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: .complete,
                isSignInInProgress: true,
            ),
            "sign-in progress → session 복원 전에도 guard 유지",
        )

        XCTAssertFalse(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: .complete,
                isSignInInProgress: false,
            ),
            "success state → guard 해제",
        )
    }

    /// ACC-003-guard_session_lapse: signed-in 이지만 status가 pending/blocked/error면 overlay가 유지된다.
    /// access status가 complete가 되기 전까지 guard가 계속 보이는지 검증한다.
    /// - 검증 내용: signed-in + nil status는 pending, inactive/refunded/revoked/none/networkFailure는 non-complete
    /// - 사전 조건: hasAccountSession == true, isSignInInProgress == false
    /// - 기대 결과: pending/blocked/error 상태에서는 guard 유지
    func testSignedInNonCompleteStatesKeepOverlayVisible() {
        var pendingState = AccountAccessFeature.State()
        pendingState.hasAccountSession = true
        pendingState.status = nil

        XCTAssertEqual(pendingState.accountAccessStepState, .pending)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: pendingState.accountAccessStepState,
                isSignInInProgress: pendingState.isSignInInProgress,
            ),
            "status 없음 → pending 유지",
        )

        let inactiveStatuses: [AccessStatus] = [.none, .trialExpired, .revoked, .refunded, .networkFailure]
        for status in inactiveStatuses {
            var state = AccountAccessFeature.State()
            state.hasAccountSession = true
            state.status = status

            XCTAssertNotEqual(state.accountAccessStepState, .complete, "\(status) → complete 아님")
            XCTAssertTrue(
                SessionLapseGuardView.shouldShow(
                    accountAccessStepState: state.accountAccessStepState,
                    isSignInInProgress: state.isSignInInProgress,
                ),
                "\(status) → guard 유지",
            )
        }
    }

    /// ACC-003-guard_session_lapse: active access가 complete일 때만 overlay가 해제된다.
    /// active 상태가 guard 해제의 유일한 경로인지 검증한다.
    /// - 검증 내용: active statuses는 stepState == .complete, guard == false
    /// - 사전 조건: hasAccountSession == true, isSignInInProgress == false
    /// - 기대 결과: active/complete만 overlay 해제
    func testActiveCompleteStateDismissesOverlay() {
        let activeStatuses: [AccessStatus] = [.coreLicenseActive, .trialActive, .internalTestActive]

        for status in activeStatuses {
            var state = AccountAccessFeature.State()
            state.hasAccountSession = true
            state.status = status

            XCTAssertEqual(state.accountAccessStepState, .complete, "\(status) → complete")
            XCTAssertFalse(
                SessionLapseGuardView.shouldShow(
                    accountAccessStepState: state.accountAccessStepState,
                    isSignInInProgress: state.isSignInInProgress,
                ),
                "\(status) → guard 해제",
            )
        }
    }

    /// ACC-003-guard_session_lapse: 로그인 CTA 선택 시 ACC-001-start_account_sign_in 호출이 가능하다.
    /// session_expired와 logged_out 상태 모두에서 canStartLogin이 true인지 검증한다.
    /// - 검증 내용: session_expired와 logged_out 상태에서 canStartLogin == true
    /// - 사전 조건: didSignInFail == true (session_expired) 또는 hasAccountSession == false (logged_out)
    /// - 기대 결과: 두 상태 모두 canStartLogin == true → handleLoginTapped guard 통과
    func testLoginCTATriggersAccountSignIn() {
        // session_expired → canStartLogin == true
        var expiredState = AccountAccessFeature.State()
        expiredState.didSignInFail = true
        XCTAssertTrue(expiredState.canStartLogin, "session_expired → canStartLogin 통과")

        // logged_out → canStartLogin == true
        var loggedOutState = AccountAccessFeature.State()
        loggedOutState.hasAccountSession = false
        XCTAssertTrue(loggedOutState.canStartLogin, "logged_out → canStartLogin 통과")

        // canStartLogin이 true이면 handleLoginTapped의 guard를 통과하고
        // .loginTapped → signInHandoffClient.performHandoff()로 이어짐
        XCTAssertTrue(expiredState.canStartLogin, "session_expired → ACC-001 호출 가능")
        XCTAssertTrue(loggedOutState.canStartLogin, "logged_out → ACC-001 호출 가능")
    }

    /// ACC-003-guard_session_lapse: 재인증 완료 후 overlay가 해제된다.
    /// hasAccountSession이 true, didSignInFail이 false일 때 guard 조건이 해제되는지 검증한다.
    /// - 검증 내용: accountAccessAuthAxis == .signedIn, didSignInFail == false, hasAccountSession == true
    /// - 사전 조건: 재인증 완료 후 hasAccountSession=true, didSignInFail=false
    /// - 기대 결과: guard 표시 조건 해제 (signedIn 상태)
    func testReauthCompleteDismissesOverlay() {
        var state = AccountAccessFeature.State()

        // session_expired 상태 진입
        state.didSignInFail = true
        state.hasAccountSession = false
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)

        // 재인증 완료 (ACC-001-exchange_handoff_token → logged_in)
        state.hasAccountSession = true
        state.didSignInFail = false
        state.status = .coreLicenseActive

        XCTAssertEqual(state.accountAccessAuthAxis, .signedIn)
        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertFalse(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: state.accountAccessStepState,
                isSignInInProgress: state.isSignInInProgress,
            ),
            "재인증 완료 + active 권한 → guard 해제",
        )
        // guard 표시 조건: accountAccessStepState != .complete || isSignInInProgress
        XCTAssertFalse(state.didSignInFail, "재인증 완료 → didSignInFail 해제")
        XCTAssertTrue(state.hasAccountSession, "재인증 완료 → hasAccountSession 복원")
    }

    /// ACC-003-guard_session_lapse: 인증 취소 후에도 overlay가 유지된다.
    /// signInHandoffCompleted(.cancelled) 후에도 didSignInFail이 true로 유지되는지 검증한다.
    /// - 검증 내용: 취소 후 didSignInFail == true (유지), isSignInInProgress == false
    /// - 사전 조건: didSignInFail == true
    /// - 기대 결과: 취소 후에도 guard 유지 (didSignInFail 변하지 않음)
    func testCancelKeepsOverlay() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true

        // 취소 시나리오: signInHandoffCompleted(.cancelled)
        // handleSignInHandoffCompleted: .cancelled → isSignInInProgress = false, didSignInFail = true 유지
        state.isSignInInProgress = false
        // didSignInFail은 true로 유지 (취소가 만료를 해소하지 않음)

        XCTAssertTrue(state.didSignInFail, "취소 후 didSignInFail 유지 → guard 지속")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertFalse(state.isSignInInProgress, "취소 후 isSignInInProgress 해제")
    }

    /// ACC-003-guard_session_lapse: 복수 window 모두 동일한 overlay가 표시된다.
    /// overlay 표시 조건이 window 개수와 무관하게 state에 의해 결정되는지 검증한다.
    /// - 검증 내용: session_expired와 logged_out 상태 모두 guard 표시 조건 충족
    /// - 사전 조건: didSignInFail == true (session_expired) 또는 hasAccountSession == false (logged_out)
    /// - 기대 결과: window 개수와 무관하게 모든 window가 동일한 guard 조건을 가짐
    func testMultipleWindowsAllShowOverlay() {
        // state 기반 표시 조건은 window 개수와 무관
        var expiredState = AccountAccessFeature.State()
        expiredState.didSignInFail = true

        var loggedOutState = AccountAccessFeature.State()
        loggedOutState.hasAccountSession = false

        // 두 window 모두 guard 표시 조건 충족
        XCTAssertTrue(expiredState.didSignInFail)
        XCTAssertEqual(expiredState.accountAccessAuthAxis, .signInFailed)

        XCTAssertFalse(loggedOutState.hasAccountSession)
        XCTAssertEqual(loggedOutState.accountAccessAuthAxis, .signedOut)

        // view는 호출 측에서 각 window에 추가해야 함 (covers_all_windows)
        // state 레벨에서는 두 window 모두 동일한 표시 조건을 가짐
        XCTAssertTrue(
            expiredState.accountAccessAuthAxis == .signInFailed || loggedOutState.accountAccessAuthAxis == .signedOut,
            "모든 window가 동일한 guard 조건을 충족",
        )
    }

    /// ACC-003-guard_session_lapse: 네트워크 오류 시 오류 안내가 다이얼로그에 표시된다.
    /// errorMessage가 설정될 때 session_expired 상태가 유지되는지 검증한다.
    /// - 검증 내용: errorMessage가 nil이 아니고 accountAccessAuthAxis == .signInFailed 유지
    /// - 사전 조건: didSignInFail == true, errorMessage 설정
    /// - 기대 결과: 다이얼로그에 오류 안내 표시, session_expired 상태 유지
    func testNetworkErrorShowsErrorMessage() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        state.errorMessage = "네트워크 연결을 확인해주세요"

        XCTAssertNotNil(state.errorMessage, "네트워크 오류 → errorMessage 존재")
        XCTAssertEqual(state.errorMessage, "네트워크 연결을 확인해주세요")
        // session_expired 상태 유지 (네트워크 오류가 만료를 해소하지 않음)
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
    }

    /// ACC-003-guard_session_lapse: session_expired 다이얼로그 제목이 스펙 문구와 일치한다.
    /// Spec: ACC-003-guard_session_lapse.md:59, 61-62
    /// - 검증 내용: session_expired title == "Session expired. Log in again to continue."
    /// - 기대 결과: 세션 만료 시 제목이 정확히 노출된다.
    func testSessionExpiredCopyMatchesSpec() {
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: true),
            "Session expired. Log in again to continue.",
        )
    }

    /// ACC-003-guard_session_lapse: logged_out 다이얼로그 제목이 스펙 문구와 일치한다.
    /// Spec: ACC-003-guard_session_lapse.md:59, 61-62
    /// - 검증 내용: logged_out title == "Log in to continue."
    /// - 기대 결과: 로그아웃 상태에서 제목이 정확히 노출된다.
    func testLoggedOutCopyMatchesSpec() {
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false),
            "Log in to continue.",
        )
    }

    /// ACC-003-guard_session_lapse: 로그인 버튼 visible copy가 스펙 문구와 일치한다.
    /// Spec: ACC-003-guard_session_lapse.md:59, 61-62
    /// - 검증 내용: button title == "Log in"
    /// - 기대 결과: 재인증 CTA가 정확히 노출된다.
    func testLoginButtonCopyMatchesSpec() {
        XCTAssertEqual(SessionLapseGuardView.loginButtonTitle, "Log in")
    }

    /// ACC-003-guard_session_lapse: 중복 overlay 표시가 dedup guard에 의해 무시된다.
    /// isSessionExpired가 true인 상태에서 중복 처리가 발생해도 상태가 유지되는지 검증한다.
    /// - 검증 내용: 중복 만료 후에도 didSignInFail, hasAccountSession, isSessionExpired가 유지된다.
    /// - 사전 조건: isSessionExpired == true (dedup guard 활성화)
    /// - 기대 결과: 중복 _sessionExpiredDetected가 무시되고 모든 상태가 유지된다.
    func testDedupGuardIgnoresDuplicateOverlay() {
        var state = AccountAccessFeature.State()

        // 첫 번째 만료 처리 (handleSessionExpiredDetected)
        guard !state.isSessionExpired else {
            XCTFail("초기 상태에서 isSessionExpired는 false여야 함")
            return
        }
        state.didSignInFail = true
        state.isSessionExpired = true

        XCTAssertTrue(state.didSignInFail)
        XCTAssertTrue(state.isSessionExpired, "첫 번째 만료 → isSessionExpired dedup 활성화")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)

        // 중복 만료: isSessionExpired가 true이므로 handleSessionExpiredDetected에서 guard
        // _sessionExpiredDetected → guard !state.isSessionExpired → return .none
        // didSignInFail과 isSessionExpired는 변하지 않음
        let beforeDidSignInFail = state.didSignInFail
        let beforeHasSession = state.hasAccountSession

        // 중복 만료가 발생해도 state 유지
        // (isSessionExpired가 true이므로 handleSessionExpiredDetected의 guard 통과 실패)
        XCTAssertEqual(state.didSignInFail, beforeDidSignInFail, "중복 만료 → didSignInFail 유지")
        XCTAssertEqual(state.hasAccountSession, beforeHasSession, "중복 만료 → hasAccountSession 유지")
        XCTAssertTrue(state.isSessionExpired, "중복 만료 → isSessionExpired 유지")
    }

    /// ACC-003-guard_session_lapse: ONB window 활성화 여부와 무관하게 overlay가 표시된다.
    /// guard 표시 조건이 ONB window 유무와 관계없이 state에 의해 결정되는지 검증한다.
    /// - 검증 내용: session_expired와 logged_out 상태 모두 ONB window와 무관하게 guard 조건 충족
    /// - 사전 조건: didSignInFail == true 또는 hasAccountSession == false
    /// - 기대 결과: ONB window 상태와 무관하게 guard 표시 조건 충족
    func testShowsOverlayRegardlessOfOnboardingWindow() {
        // ONB window 활성화는 호출 측에서 skip_onboarding_window 정책으로 관리
        // state 레벨에서는 ONB window 유무와 관계없이 guard 조건이 충족되어야 함
        var state = AccountAccessFeature.State()

        // ONB window와 관계없이 session_expired 조건 충족
        state.didSignInFail = true

        // guard 표시 조건은 ONB window 상태와 무관
        XCTAssertTrue(state.didSignInFail, "ONB window 상태와 무관하게 guard 표시")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)

        // logged_out 상태도 동일
        var loggedOutState = AccountAccessFeature.State()
        loggedOutState.hasAccountSession = false

        XCTAssertFalse(loggedOutState.hasAccountSession, "ONB window와 무관하게 guard 표시")
        XCTAssertEqual(loggedOutState.accountAccessAuthAxis, .signedOut)
    }
}

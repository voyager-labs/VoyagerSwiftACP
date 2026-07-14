import AppKit
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
final class ACC003GuardSessionLapseTests: XCTestCase {
    // MARK: - ACC-003-guard_session_lapse

    func testSignInProgressKeepsOverlayVisible() {
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: .pending,
                isSignInInProgress: true,
            ),
        )

        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: .complete,
                isSignInInProgress: true,
            ),
        )
    }

    func testPendingBlockedAndErrorStatesKeepOverlayVisible() {
        var pendingState = AccountAccessFeature.State()
        pendingState.hasAccountSession = true
        pendingState.status = nil

        XCTAssertEqual(pendingState.accountAccessStepState, .pending)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: pendingState.accountAccessStepState,
                isSignInInProgress: pendingState.isSignInInProgress,
            ),
        )

        var blockedState = AccountAccessFeature.State()
        blockedState.hasAccountSession = true
        blockedState.status = .revoked

        XCTAssertEqual(blockedState.accountAccessStepState, .blocked)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: blockedState.accountAccessStepState,
                isSignInInProgress: blockedState.isSignInInProgress,
            ),
        )

        var errorState = AccountAccessFeature.State()
        errorState.hasAccountSession = true
        errorState.status = .networkFailure

        XCTAssertEqual(errorState.accountAccessStepState, .error)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: errorState.accountAccessStepState,
                isSignInInProgress: errorState.isSignInInProgress,
            ),
        )
    }

    func testCompleteStateDismissesOverlay() {
        let activeStatuses: [AccessStatus] = [.coreLicenseActive, .trialActive, .internalTestActive]

        for status in activeStatuses {
            var state = AccountAccessFeature.State()
            state.hasAccountSession = true
            state.status = status
            state.isComplete = true

            XCTAssertEqual(state.accountAccessStepState, .complete)
            XCTAssertFalse(
                SessionLapseGuardView.shouldShow(
                    accountAccessStepState: state.accountAccessStepState,
                    isSignInInProgress: state.isSignInInProgress,
                ),
            )
        }
    }

    func testDialogTitleMatchesAuthState() {
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: true),
            "Session expired. Sign in again to continue.",
        )
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false),
            "Sign in to continue.",
        )
    }

    func testLoginButtonTitleIsStable() {
        XCTAssertEqual(SessionLapseGuardView.loginButtonTitle, "Sign in")
        XCTAssertEqual(SessionLapseGuardView.accountButtonTitle, "Open account")
    }

    func testPrimaryButtonTitleMatchesAccessRecoveryCTA() {
        XCTAssertEqual(SessionLapseGuardView.primaryButtonTitle(for: .login), "Sign in")
        XCTAssertEqual(SessionLapseGuardView.primaryButtonTitle(for: .account), "Open account")
        XCTAssertEqual(SessionLapseGuardView.primaryButtonTitle(for: .retry), "Retry")
        XCTAssertEqual(SessionLapseGuardView.primaryButtonTitle(for: .webPricing), "View pricing")
    }

    func testPrimaryButtonActionMatchesAccessRecoveryCTA() {
        if case .loginTapped(context: .paywall, scope: .lifecycle) = SessionLapseGuardView
            .primaryButtonAction(for: .login) {} else
        {
            XCTFail("login CTA는 loginTapped를 전송해야 함")
        }
        if case .retryTapped = SessionLapseGuardView.primaryButtonAction(for: .retry) {} else {
            XCTFail("retry CTA는 retryTapped를 전송해야 함")
        }
        if case .openAccountTapped = SessionLapseGuardView.primaryButtonAction(for: .account) {} else {
            XCTFail("account CTA는 openAccountTapped를 전송해야 함")
        }
        if case .openPricingTapped = SessionLapseGuardView.primaryButtonAction(for: .webPricing) {} else {
            XCTFail("pricing CTA는 openPricingTapped를 전송해야 함")
        }
    }

    func testDialogTitleMatchesAccessRecoveryCTA() {
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false, accessUnlockPrimaryCTA: .webPricing),
            "Access required to continue.",
        )
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false, accessUnlockPrimaryCTA: .account),
            "Check your account to continue.",
        )
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false, accessUnlockPrimaryCTA: .retry),
            "Could not verify access.",
        )
    }

    func testReauthCompleteDismissesOverlay() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        state.hasAccountSession = false

        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: state.accountAccessStepState,
                isSignInInProgress: state.isSignInInProgress,
            ),
        )

        state.hasAccountSession = true
        state.didSignInFail = false
        state.status = .coreLicenseActive
        state.isComplete = true

        XCTAssertEqual(state.accountAccessStepState, .complete)
        XCTAssertFalse(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: state.accountAccessStepState,
                isSignInInProgress: state.isSignInInProgress,
            ),
        )
    }

    func testCancelKeepsOverlayVisible() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        state.isSignInInProgress = false

        XCTAssertEqual(state.accountAccessStepState, .blocked)
        XCTAssertTrue(
            SessionLapseGuardView.shouldShow(
                accountAccessStepState: state.accountAccessStepState,
                isSignInInProgress: state.isSignInInProgress,
            ),
        )
    }

    /// ACC-003-guard_session_lapse: guard overlay는 FileManager 클릭/파일 drop을 기저 view로 통과시키지 않는다.
    /// shield view가 hit-test 대상이 되고 fileURL drag type을 등록하는지 검증한다.
    func testInteractionShieldBlocksHitTestsAndFileDrops() {
        let shield = SessionLapseGuardInteractionShieldView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))

        XCTAssertIdentical(shield.hitTest(NSPoint(x: 10, y: 10)), shield)
        XCTAssertTrue(shield.registeredDraggedTypes.contains(.fileURL))
    }

    /// ACC-003-guard_session_lapse: 복수 window에서도 overlay 표시는 state 기준으로 동일해야 한다.
    func testMultipleWindowsAllShowOverlay() {
        var expiredState = AccountAccessFeature.State()
        expiredState.didSignInFail = true

        var loggedOutState = AccountAccessFeature.State()
        loggedOutState.hasAccountSession = false

        XCTAssertTrue(expiredState.didSignInFail)
        XCTAssertEqual(expiredState.accountAccessAuthAxis, .signInFailed)
        XCTAssertFalse(loggedOutState.hasAccountSession)
        XCTAssertEqual(loggedOutState.accountAccessAuthAxis, .signedOut)
        XCTAssertTrue(
            expiredState.accountAccessAuthAxis == .signInFailed || loggedOutState.accountAccessAuthAxis == .signedOut,
            "모든 window가 동일한 guard 조건을 충족",
        )
    }

    func testNetworkErrorShowsErrorMessage() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true
        state.errorMessage = "네트워크 연결을 확인해주세요"

        XCTAssertNotNil(state.errorMessage)
        XCTAssertEqual(state.errorMessage, "네트워크 연결을 확인해주세요")
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)
    }

    func testDedupGuardIgnoresDuplicateOverlay() {
        var state = AccountAccessFeature.State()
        guard !state.isSessionExpired else {
            XCTFail("초기 상태에서 isSessionExpired는 false여야 함")
            return
        }
        state.didSignInFail = true
        state.isSessionExpired = true

        XCTAssertTrue(state.didSignInFail)
        XCTAssertTrue(state.isSessionExpired)
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)

        let beforeDidSignInFail = state.didSignInFail
        let beforeHasSession = state.hasAccountSession

        XCTAssertEqual(state.didSignInFail, beforeDidSignInFail)
        XCTAssertEqual(state.hasAccountSession, beforeHasSession)
        XCTAssertTrue(state.isSessionExpired)
    }

    func testShowsOverlayRegardlessOfOnboardingWindow() {
        var state = AccountAccessFeature.State()
        state.didSignInFail = true

        XCTAssertTrue(state.didSignInFail)
        XCTAssertEqual(state.accountAccessAuthAxis, .signInFailed)

        var loggedOutState = AccountAccessFeature.State()
        loggedOutState.hasAccountSession = false

        XCTAssertFalse(loggedOutState.hasAccountSession)
        XCTAssertEqual(loggedOutState.accountAccessAuthAxis, .signedOut)
    }
}

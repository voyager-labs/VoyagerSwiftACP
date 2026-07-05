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
            "Session expired. Log in again to continue.",
        )
        XCTAssertEqual(
            SessionLapseGuardView.dialogTitle(didSignInFail: false),
            "Log in to continue.",
        )
    }

    func testLoginButtonTitleIsStable() {
        XCTAssertEqual(SessionLapseGuardView.loginButtonTitle, "Log in")
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

    func testInteractionShieldBlocksHitTestsAndFileDrops() {
        let shield = SessionLapseGuardInteractionShieldView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))

        XCTAssertIdentical(shield.hitTest(NSPoint(x: 10, y: 10)), shield)
        XCTAssertTrue(shield.registeredDraggedTypes.contains(.fileURL))
    }
}

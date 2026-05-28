import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesLicenseAuth
import XCTest

/// 앱 생명주기 계약 — 액션/상태 구조와 Equatable 준수를 검증.
@MainActor
final class AppLifecycleFeatureContractTests: XCTestCase {
    /// testInitialStateHasDidStartHelperFalse 테스트 동작을 검증한다.
    func testInitialStateHasDidStartHelperFalse() {
        let state = AppLifecycleState()
        XCTAssertFalse(state.didStartHelper)
        XCTAssertNil(state.terminationAttemptID)
        XCTAssertFalse(state.isCheckingLicenseAuth)
        XCTAssertNil(state.lastLicenseAuthStatus)
        XCTAssertFalse(state.licenseAuthGateResolved)
    }

    /// testStateIsEquatable 테스트 동작을 검증한다.
    func testStateIsEquatable() {
        let id = UUID()
        let state1 = AppLifecycleState(
            didStartHelper: true,
            terminationAttemptID: id,
            isCheckingLicenseAuth: true,
            lastLicenseAuthStatus: .coreLicenseActive,
            licenseAuthGateResolved: true,
        )
        let state2 = AppLifecycleState(
            didStartHelper: true,
            terminationAttemptID: id,
            isCheckingLicenseAuth: true,
            lastLicenseAuthStatus: .coreLicenseActive,
            licenseAuthGateResolved: true,
        )
        XCTAssertEqual(state1, state2)
    }

    /// testLaunchActionsHaveProperStructure 테스트 동작을 검증한다.
    func testLaunchActionsHaveProperStructure() {
        XCTAssertTrue(AppLifecycleAction.launch(.willFinishLaunching).is(\.launch.willFinishLaunching))
        XCTAssertTrue(AppLifecycleAction.launch(.didFinishLaunching).is(\.launch.didFinishLaunching))
    }

    /// testReopenActionHasProperStructure 테스트 동작을 검증한다.
    func testReopenActionHasProperStructure() {
        let reopenAction = AppLifecycleAction.launch(.appReopen(hasVisibleWindows: true))
        XCTAssertTrue(reopenAction.is(\.launch.appReopen))
    }

    func testLicenseAuthGateActionsHaveProperStructure() {
        XCTAssertTrue(AppLifecycleAction.licenseAuthGate(.checkAccessStatus).is(\.licenseAuthGate.checkAccessStatus))
        XCTAssertTrue(AppLifecycleAction.licenseAuthGate(.showUnlockSurface).is(\.licenseAuthGate.showUnlockSurface))

        let responseAction = AppLifecycleAction.licenseAuthGate(.licenseAuthStatusResponse(.success(
            LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]),
        )))
        XCTAssertTrue(responseAction.is(\.licenseAuthGate.licenseAuthStatusResponse))

        let grantedAction = AppLifecycleAction.licenseAuthGate(.licenseAuthGranted(snapshot: LicenseAuthStatusSnapshot(
            status: .coreLicenseActive,
            entitlements: [.coreLicense],
        )))
        XCTAssertTrue(grantedAction.is(\.licenseAuthGate.licenseAuthGranted))
    }

    /// testTerminationActionsHaveProperStructure 테스트 동작을 검증한다.
    func testTerminationActionsHaveProperStructure() {
        let attemptID = UUID()
        let result = QuitConfirmationResult(shouldQuit: true, isAlertBeforeQuitEnabled: false)

        XCTAssertTrue(AppLifecycleAction.termination(.requestTermination).is(\.termination.requestTermination))

        let responseAction = AppLifecycleAction.termination(.quitConfirmationResponse(
            attemptID: attemptID,
            result: result,
        ))
        XCTAssertTrue(responseAction.is(\.termination.quitConfirmationResponse))

        let startCleanupAction = AppLifecycleAction.termination(.startTerminationCleanup(attemptID: attemptID))
        XCTAssertTrue(startCleanupAction.is(\.termination.startTerminationCleanup))

        let completeAction = AppLifecycleAction.termination(.completeTerminationAttempt(
            attemptID: attemptID,
            shouldTerminate: true,
        ))
        XCTAssertTrue(completeAction.is(\.termination.completeTerminationAttempt))

        XCTAssertTrue(AppLifecycleAction.termination(.willTerminate).is(\.termination.willTerminate))
    }

    /// testDelegateActionsHaveProperStructure 테스트 동작을 검증한다.
    func testDelegateActionsHaveProperStructure() {
        let openInitialAction = AppLifecycleAction.delegate(.openInitialWindowIfNeeded)
        XCTAssertTrue(openInitialAction.is(\.delegate))

        let reopenAction = AppLifecycleAction.delegate(.reopenWindowIfNeeded(hasVisibleWindows: true))
        XCTAssertTrue(reopenAction.is(\.delegate))

        let startHelperAction = AppLifecycleAction.delegate(.startHelperIfNeeded)
        XCTAssertTrue(startHelperAction.is(\.delegate))
    }
}

// swiftlint:disable file_length
import Foundation

import ComposableArchitecture
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_name
// swiftlint:disable type_body_length
@MainActor
final class ONB003ConfigureRequiredPermissionsFeatureTests: XCTestCase {
    // swiftlint:enable type_name
    // MARK: - ONB-003-show_onboarding_permission_status

    /// Covers initial permission status display on appear.
    func testOnAppearLoadsHelperFolderAccessStatus() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.receive(\.launchAtLoginStateLoaded)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// Covers initial status when FDA is unknown.
    func testOnAppearWithFDAUnknownShowsNeedsAction() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .unknown })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse)
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
        }
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertNotNil(store.state.nextDisabledMessage)
        XCTAssertEqual(store.state.fullDiskAccessStatus, .unknown)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// Covers helper folder access partially granted status display.
    func testOnAppearWithPartialHelperAccessShowsPartial() async {
        let partialAccess = FolderAccessResult(
            desktop: .granted,
            documents: .granted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { partialAccess },
                requestAccess: { partialAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = partialAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertEqual(store.state.helperFolderAccessStatus, .partial)
        XCTAssertTrue(store.state.showsHelperFolderAccessAction)
        XCTAssertFalse(store.state.isComplete)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// Covers status display when all permissions are denied.
    func testOnAppearWithAllDeniedShowsCorrectStatus() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .denied })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .denied
        }
        await store.receive(\.helperFolderAccessStatusLoaded)
        await store.receive(\.launchAtLoginStateLoaded)

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        XCTAssertEqual(store.state.helperFolderAccessStatus, .notGranted)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// RED: Fresh state → isComplete stays false until both FDA and helper are granted.
    func testInitialStatusIsNotCompleteUntilAllChecksPass() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .needsAction })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }
        await store.receive(\.launchAtLoginStateLoaded)

        // FDA not granted → isComplete remains false
        XCTAssertFalse(store.state.isComplete)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// RED: Helper folder access not granted for some folders → isComplete stays false.
    func testHelperFolderAccessDeniedBlocksCompletion() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded)
        await store.receive(\.launchAtLoginStateLoaded)

        // FDA granted but helper denied → isComplete still false
        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }

    // MARK: - ONB-003-refresh_onboarding_permission_status

    /// Covers observation lifecycle cleanup on disappear.
    func testOnDisappearCancelsAppActiveObservation() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .unknown })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse)
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
        }
        await store.receive(\.launchAtLoginStateLoaded)

        await store.send(.onDisappear)
        await store.finish()
    }

    /// Covers status refresh on app activation.
    func testAppDidBecomeActiveRefreshesHelperFolderAccessStatus() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.finish()
    }

    /// Covers refresh after FDA grant updates isComplete correctly.
    func testRefreshAfterFDAGrantMarksComplete() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    /// Covers refresh after helper folder access change to denied.
    func testRefreshAfterHelperFolderAccessChangeUpdatesStatus() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { deniedAccess },
                requestAccess: { deniedAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded)

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.helperFolderAccessStatus, .notGranted)
        await store.finish()
    }

    /// Covers that refresh does not reset Launch at Login state.
    func testRefreshDoesNotResetLaunchAtLoginState() async {
        var initialState = PermissionsFeature.State()
        initialState.launchAtLoginEnabled = true

        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.isComplete = true
        }

        XCTAssertTrue(store.state.launchAtLoginEnabled)
        await store.finish()
    }

    /// RED: Initially needsAction → after refresh returns .granted → isComplete becomes true.
    func testRefreshAfterGrantingFDAClearsErrorAndCompletes() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        // Seed: FDA = needsAction, helper = granted → not complete
        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }
        XCTAssertFalse(store.state.isComplete)

        // Refresh: FDA now granted
        await store.send(.appDidBecomeActive)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.finish()
    }

    // MARK: - ONB-003-request_onboarding_permission_access

    /// Covers FDA gating behavior for Next button.
    func testFullDiskAccessGatesNext() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }

        XCTAssertEqual(store.state.nextDisabledMessage, "Turn on Full Disk Access to continue.")

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = true
        }

        XCTAssertNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// Covers FDA denied state after user attempts to enable.
    func testFullDiskAccessDeniedAfterAttempt() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(true)) { state in
            state.systemSettingsError = nil
            state.hasAttemptedFullDiskAccessEnable = true
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        await store.finish()
    }

    /// Covers error display when System Settings fails to open.
    func testOpenSystemSettingsFailureShowsError() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(false)) { state in
            state.systemSettingsError = "We couldn't open System Settings. Please open it manually."
            state.hasAttemptedFullDiskAccessEnable = false
        }

        await store.finish()
    }

    /// Covers Launch at Login toggle success (non-gating permission).
    func testLaunchAtLoginToggleSuccess() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
            state.launchAtLoginError = nil
        }

        await store.receive(\.launchAtLoginUpdateSucceeded)

        XCTAssertNil(store.state.launchAtLoginError)
        await store.finish()
    }

    /// Covers Launch at Login toggle failure (non-gating permission).
    func testLaunchAtLoginToggleFailure() async {
        struct TestError: Error {}

        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in
                throw TestError()
            })
        }

        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
            state.launchAtLoginError = nil
        }

        await store.receive(\.launchAtLoginUpdateFailed) { state in
            state.launchAtLoginEnabled = false
            state.launchAtLoginError =
                "We couldn't update your Login Items. Manage this in System Settings."
        }

        await store.finish()
    }

    /// Covers FDA request opens system settings.
    func testOpenSystemSettingsTappedCallsSystemSettingsClient() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
        }

        await store.send(.openSystemSettingsTapped)
        await store.receive(\.systemSettingsOpenResult) { state in
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.finish()
    }

    /// Covers helper folder access request flow.
    func testRequestHelperFolderAccessTappedSucceeds() async {
        var initialState = PermissionsFeature.State()
        initialState.fullDiskAccessStatus = .granted

        let store = TestStore(initialState: initialState) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.isRequestingHelperFolderAccess = true
        }
        await store.receive(\.helperFolderAccessResponse) { state in
            state.isRequestingHelperFolderAccess = false
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.finish()
    }

    /// Covers helper folder access request returning partial.
    func testRequestHelperFolderAccessTappedReturnsPartial() async {
        let partialAccess = FolderAccessResult(
            desktop: .granted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { partialAccess },
                requestAccess: { partialAccess },
            )
        }

        await store.send(.requestHelperFolderAccessTapped) { state in
            state.helperFolderAccessError = nil
            state.isRequestingHelperFolderAccess = true
        }
        await store.receive(\.helperFolderAccessResponse) { state in
            state.isRequestingHelperFolderAccess = false
            state.helperFolderAccess = partialAccess
            state.helperFolderAccessError =
                "VoyagerHelper still needs Desktop, Documents, and Downloads access."
            state.isComplete = false
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertNotNil(store.state.helperFolderAccessError)
        await store.finish()
    }

    /// Covers FDA blocks Next when denied.
    func testFDABlocksNextWhenDenied() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.denied)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Turn on Full Disk Access to continue.",
        )
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// Covers helper access blocks Next when not granted.
    func testHelperAccessBlocksNextWhenNotGranted() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.send(.helperFolderAccessStatusLoaded(deniedAccess))

        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue.",
        )
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// Covers Launch at Login does NOT block Next.
    func testLaunchAtLoginDoesNotBlockNextWhenDisabled() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }
        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.isComplete = true
        }
        await store.send(.launchAtLoginStateLoaded(false))

        XCTAssertTrue(store.state.isComplete)
        XCTAssertNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// Covers FDA request transitions from denied to granted (retry success).
    func testFDARetryFromDeniedToGranted() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.systemSettingsOpenResult(true)) { state in
            state.hasAttemptedFullDiskAccessEnable = true
        }
        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .denied
            state.isComplete = false
        }

        XCTAssertEqual(store.state.fullDiskAccessStatus, .denied)
        XCTAssertNotNil(store.state.nextDisabledMessage)

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
        }

        XCTAssertNotNil(store.state.nextDisabledMessage)
        await store.finish()
    }

    /// Covers that Launch at Login toggle does not gate isComplete.
    func testLaunchAtLoginDoesNotGateCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = true
        }

        // Toggle Launch at Login -> isComplete stays true
        await store.send(.launchAtLoginToggled(true)) { state in
            state.launchAtLoginEnabled = true
        }
        await store.receive(\.launchAtLoginUpdateSucceeded)
        XCTAssertTrue(store.state.isComplete)

        await store.send(.launchAtLoginToggled(false)) { state in
            state.launchAtLoginEnabled = false
        }
        await store.receive(\.launchAtLoginUpdateSucceeded)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }

    /// RED: FDA = needsAction, helper = granted → nextDisabledMessage is non-nil.
    func testFDARequiredGateBlocksNextButton() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.helperFolderAccessStatusLoaded(kGrantedHelperAccess)) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = false
        }

        await store.send(.fullDiskAccessStatusResponse(.needsAction)) { state in
            state.fullDiskAccessStatus = .needsAction
            state.isComplete = false
        }

        XCTAssertEqual(store.state.nextDisabledMessage, "Turn on Full Disk Access to continue.")
        XCTAssertFalse(store.state.isComplete)

        await store.finish()
    }

    /// RED: Helper not granted → blocks even when FDA is granted.
    func testHelperFolderAccessRequiredGateBlocksNext() async {
        let deniedAccess = FolderAccessResult(
            desktop: .notGranted,
            documents: .notGranted,
            downloads: .notGranted,
        )
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        }

        await store.send(.fullDiskAccessStatusResponse(.granted)) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }

        await store.send(.helperFolderAccessStatusLoaded(deniedAccess))

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Grant VoyagerHelper access to Desktop, Documents, and Downloads to continue.",
        )

        await store.finish()
    }

    /// RED: FDA granted + helper granted + Launch at Login disabled → isComplete = true.
    func testLaunchAtLoginNonGateDoesNotBlockCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { .granted })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { kGrantedHelperAccess },
                requestAccess: { kGrantedHelperAccess },
            )
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        await store.send(.onAppear)
        await store.receive(\.fullDiskAccessStatusResponse) { state in
            state.fullDiskAccessStatus = .granted
            state.isComplete = false
        }
        await store.receive(\.helperFolderAccessStatusLoaded) { state in
            state.helperFolderAccess = kGrantedHelperAccess
            state.helperFolderAccessError = nil
            state.isComplete = true
        }
        await store.receive(\.launchAtLoginStateLoaded)

        // Launch at Login disabled but all required permissions granted → complete
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.launchAtLoginEnabled)
        XCTAssertNil(store.state.nextDisabledMessage)

        await store.send(.onDisappear)
        await store.finish()
    }
    // swiftlint:enable type_body_length
}

// swiftlint:enable file_length

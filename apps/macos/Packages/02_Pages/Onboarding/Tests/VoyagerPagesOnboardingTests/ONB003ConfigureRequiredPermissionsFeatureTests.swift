import Foundation

import ComposableArchitecture
import VoyagerEntitiesAppPreferences
@testable import VoyagerPagesOnboarding
import XCTest

// swiftlint:disable type_name
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
}

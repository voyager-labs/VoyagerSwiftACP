import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class PermissionsFeatureTests: XCTestCase {
    func testFullDiskAccessGatesNext() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
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

    func testLaunchAtLoginDoesNotGateCompletion() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }

        // FDA granted -> isComplete = true
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

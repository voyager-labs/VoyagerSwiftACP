import ComposableArchitecture
@testable import VoyagerFeaturesUpdateVersion
import VoyagerShared
import XCTest

// VOY-202 Task 11: Updater Feature Regression Anchor
// UpdaterFeature is a REGRESSION ANCHOR - not a direct refactoring target for VOY-202.
// These tests lock the state/action contracts to prevent accidental changes.

@MainActor
final class UpdaterFeatureContractTests: XCTestCase {
    // MARK: State Contract Tests

    func testInitialStateHasCorrectDefaults() {
        let state = UpdaterState()
        XCTAssertFalse(state.didConfigure)
        XCTAssertFalse(state.didStartAtLaunch)
    }

    func testStateIsEquatable() {
        let state1 = UpdaterState(didConfigure: true, didStartAtLaunch: true)
        let state2 = UpdaterState(didConfigure: true, didStartAtLaunch: true)
        XCTAssertEqual(state1, state2)

        let state3 = UpdaterState(didConfigure: false, didStartAtLaunch: false)
        let state4 = UpdaterState(didConfigure: false, didStartAtLaunch: false)
        XCTAssertEqual(state3, state4)
    }

    // MARK: Action Contract Tests

    func testActionsHaveProperStructure() {
        let configureAction = UpdaterAction.configureAtLaunch
        XCTAssertTrue(configureAction.is(\.configureAtLaunch))

        let startAction = UpdaterAction.startAtLaunch
        XCTAssertTrue(startAction.is(\.startAtLaunch))

        let checkAction = UpdaterAction.checkForUpdates
        XCTAssertTrue(checkAction.is(\.checkForUpdates))

        let setAutoAction = UpdaterAction.setAutomaticUpdate(true)
        XCTAssertTrue(setAutoAction.is(\.setAutomaticUpdate))
    }

    // MARK: Feature Behavior Tests

    func testConfigureAtLaunchSetsDidConfigureTrue() async {
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.configure = {}
            $0.updaterClient.setAutomaticUpdate = { _ in }
        }

        await store.send(.configureAtLaunch) {
            $0.didConfigure = true
        }
    }

    func testConfigureAtLaunchIsIdempotent() async {
        var state = UpdaterState()
        state.didConfigure = true

        let store = TestStore(initialState: state) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.configure = {}
            $0.updaterClient.setAutomaticUpdate = { _ in }
        }

        await store.send(.configureAtLaunch)
    }

    func testStartAtLaunchSetsDidStartAtLaunchTrue() async {
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.startAtLaunch = {}
        }

        await store.send(.startAtLaunch) {
            $0.didStartAtLaunch = true
        }
    }

    func testStartAtLaunchIsIdempotent() async {
        var state = UpdaterState()
        state.didStartAtLaunch = true

        let store = TestStore(initialState: state) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.startAtLaunch = {}
        }

        await store.send(.startAtLaunch)
    }

    func testCheckForUpdatesCallsClient() async {
        var checkForUpdatesCalled = false

        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.checkForUpdates = {
                await MainActor.run { checkForUpdatesCalled = true }
            }
        }

        await store.send(.checkForUpdates)
        XCTAssertTrue(checkForUpdatesCalled)
    }

    func testSetAutomaticUpdateCallsClient() async {
        actor ValueHolder {
            var value: Bool?
            func set(_ newValue: Bool) { value = newValue }
            func get() -> Bool? { value }
        }
        let holder = ValueHolder()

        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.setAutomaticUpdate = { enabled in
                await holder.set(enabled)
            }
        }

        await store.send(.setAutomaticUpdate(true))
        let value1 = await holder.get()
        XCTAssertTrue(value1 ?? false)

        await store.send(.setAutomaticUpdate(false))
        let value2 = await holder.get()
        XCTAssertFalse(value2 ?? true)
    }
}

import ComposableArchitecture
@testable import VoyagerFeaturesUpdateVersion
import VoyagerShared
import XCTest

// VOY-202 작업 11: Updater 기능 회귀 앵커
// UpdaterFeature는 회귀 앵커입니다 - VOY-202의 직접적인 리팩토링 대상이 아닙니다.
// 이 테스트들은 우발적인 변경을 방지하기 위해 state/action 계약을 고정합니다.

@MainActor
final class UpdaterFeatureContractTests: XCTestCase {
    // MARK: - State 계약 테스트

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

    // MARK: - Action 계약 테스트

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

    // MARK: - 기능 동작 테스트

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

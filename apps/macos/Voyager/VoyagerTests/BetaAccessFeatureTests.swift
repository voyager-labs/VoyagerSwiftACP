import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class BetaAccessFeatureTests: XCTestCase {
    func testMissingInputDoesNotAdvanceScenario() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.checkTapped)

        XCTAssertEqual(store.state.scenarioIndex, 0)
        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)

        await store.finish()
    }

    func testScenarioRotation() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("tester@example.com")) { state in
            state.email = "tester@example.com"
        }

        await store.send(.tokenChanged("token")) { state in
            state.token = "token"
            state.reason = .none
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
            state.scenarioIndex = 1
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .mismatch
            state.isComplete = false
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
            state.scenarioIndex = 2
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .tokenAlreadyRegistered
            state.isComplete = false
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
            state.scenarioIndex = 3
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .none
            state.isComplete = false
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
            state.scenarioIndex = 0
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }
}

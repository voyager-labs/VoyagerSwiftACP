import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class BetaAccessFeatureTests: XCTestCase {
    func testMissingInputDoesNotVerify() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.checkTapped)

        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)

        await store.finish()
    }

    func testVerificationSuccess() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { email, token in
                XCTAssertEqual(email, "tester@example.com")
                XCTAssertEqual(token, "cbt-token")
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.emailChanged("tester@example.com")) { state in
            state.email = "tester@example.com"
        }

        await store.send(.tokenChanged("cbt-token")) { state in
            state.token = "cbt-token"
            state.reason = .none
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
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

import ComposableArchitecture
@testable import VoyagerFeaturesBetaAccess
import XCTest

@MainActor
final class OnboardingBetaAccessFeatureTests: XCTestCase {
    // MARK: - ONB-002-start_access_unlock_recovery

    func testInvalidGatewayURLMapsToInvalidGatewayReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_gateway_url")
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
            state.status = .checkFailed
            state.reason = .invalidGatewayUrl
            state.isComplete = false
        }

        await store.finish()
    }
}

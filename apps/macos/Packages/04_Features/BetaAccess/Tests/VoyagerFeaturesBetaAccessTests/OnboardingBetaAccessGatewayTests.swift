// ONB-002: Core License auth/entitlement migration is future scope (project f946b2b9-0e41-4975-a55a-d5aacc11fcbd)

import ComposableArchitecture
@testable import VoyagerFeaturesBetaAccess
import XCTest

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.withLock { _value }
    }

    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}

// swiftlint:disable type_body_length
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

    func testGatewayErrorMissingTokenMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "missing_token")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .missingToken
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorInvalidTokenMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_token")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .invalidToken
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorInvalidRequestMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "invalid_request")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .invalidRequest
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorEmailMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "email_mismatch")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .emailMismatch
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorDeviceMismatchMapsToNotActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "device_mismatch")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .notActive
            state.reason = .deviceMismatch
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorAuthBackendErrorMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "auth_backend_error")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .authBackendError
            state.isComplete = false
        }

        await store.finish()
    }

    func testGatewayErrorUnknownCodeMapsToNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "some_unknown_code")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.finish()
    }

    func testRetryAfterGatewayFailureSucceeds() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.gatewayError(code: "auth_backend_error")
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .authBackendError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(counter.value, 2)
        await store.finish()
    }

    func testRetryAfterNetworkFailureRecovers() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.networkError
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
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

    func testRepeatedRetryStillRecoverable() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum < 3 {
                    throw BetaAccessVerificationError.networkError
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(counter.value, 3)
        await store.finish()
    }

    // ONB-002 auth/entitlement migration is future scope — project f946b2b9-0e41-4975-a55a-d5aacc11fcbd

    func testGatewayTimeoutMapsToCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.gatewayError(code: "timeout")
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.finish()
    }

    func testRecoveryAfterFailedVerificationAllowsRetry() async {
        let counter = AttemptCounter()
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                let attemptNum = counter.increment()
                if attemptNum == 1 {
                    throw BetaAccessVerificationError.gatewayError(code: "timeout")
                }
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .networkError
            state.isComplete = false
        }

        await store.send(.retryTapped) { state in
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
    // swiftlint:enable type_body_length
}

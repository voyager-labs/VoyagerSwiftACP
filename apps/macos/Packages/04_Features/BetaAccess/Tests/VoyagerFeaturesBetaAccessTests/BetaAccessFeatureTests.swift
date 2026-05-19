// swiftlint:disable file_length
// ONB-002: Core License auth/entitlement migration is future scope (project f946b2b9-0e41-4975-a55a-d5aacc11fcbd)

import ComposableArchitecture
@testable import VoyagerFeaturesBetaAccess
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class BetaAccessFeatureTests: XCTestCase {
    // MARK: - ONB-002-show_access_unlock_status

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

    func testInitialStateShowsNotActiveStatus() {
        let state = BetaAccessFeature.State()
        XCTAssertEqual(state.status, .notActive)
        XCTAssertEqual(state.reason, .missingInput)
        XCTAssertFalse(state.isVerifying)
        XCTAssertFalse(state.isComplete)
    }

    func testActiveStatusMessage() {
        let state = BetaAccessFeature.State(status: .active)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.statusTitle, "Active")
        XCTAssertNotNil(state.statusMessage)
        // isComplete is only set via updateStatus(), not the memberwise init
        XCTAssertFalse(state.isComplete)
    }

    func testCheckFailedStatusMessage() {
        let state = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertEqual(state.status, .checkFailed)
        XCTAssertEqual(state.statusTitle, "Check failed")
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    func testNotActiveWithMissingInputMessage() {
        let state = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertNotNil(state.statusMessage)
        XCTAssertFalse(state.isComplete)
    }

    func testLoadingStateDuringVerification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        XCTAssertTrue(store.state.isVerifying)

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertFalse(store.state.isVerifying)
        await store.finish()
    }

    func testOnAppearTriggersVerificationWhenInputsPresent() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "user@test.com",
            token: "valid-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { email, token in
                XCTAssertEqual(email, "user@test.com")
                XCTAssertEqual(token, "valid-token")
                return BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.onAppear) { state in
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

    func testOnAppearDoesNotVerifyWhenEmailEmpty() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.onAppear)

        XCTAssertEqual(store.state.status, .notActive)
        XCTAssertEqual(store.state.reason, .missingInput)
        XCTAssertFalse(store.state.isVerifying)

        await store.finish()
    }

    func testCanSubmitIsFalseWhenVerifying() {
        let state = BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            isVerifying: true,
        )
        XCTAssertFalse(state.canSubmit)
    }

    func testShowsRetryOnlyWhenCheckFailed() {
        let failed = BetaAccessFeature.State(status: .checkFailed, reason: .networkError)
        XCTAssertTrue(failed.showsRetry)

        let active = BetaAccessFeature.State(status: .active)
        XCTAssertFalse(active.showsRetry)

        let notActive = BetaAccessFeature.State(status: .notActive, reason: .missingInput)
        XCTAssertFalse(notActive.showsRetry)
    }

    // MARK: - ONB-002-apply_access_unlock_result

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

    func testVerificationResponseOkSetsActiveAndComplete() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
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

        XCTAssertEqual(store.state.status, .active)
        XCTAssertTrue(store.state.isComplete)
        XCTAssertFalse(store.state.isVerifying)
        await store.finish()
    }

    func testVerificationResponseNotOkSetsCheckFailed() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: false)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .internalError
            state.isComplete = false
        }

        XCTAssertEqual(store.state.status, .checkFailed)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    func testVerificationFailureNetworkError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.networkError
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

    func testVerificationFailureDecodingError() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.decodingError
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .internalError
            state.isComplete = false
        }

        await store.finish()
    }

    func testVerificationFailureDeviceIdUnavailable() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.deviceIdUnavailable
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .deviceIdUnavailable
            state.isComplete = false
        }

        await store.finish()
    }

    func testVerificationFailureInvalidRequest() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                throw BetaAccessVerificationError.invalidRequest
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .checkFailed
            state.reason = .invalidRequest
            state.isComplete = false
        }

        await store.finish()
    }

    func testInputChangeClearsMissingInputReasonWhenBothFilled() async {
        let store = TestStore(initialState: BetaAccessFeature.State()) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = .mock
        }

        await store.send(.emailChanged("a@b.com")) { state in
            state.email = "a@b.com"
        }

        await store.send(.tokenChanged("tok")) { state in
            state.token = "tok"
            state.reason = .none
        }

        XCTAssertEqual(store.state.reason, .none)
        await store.finish()
    }

    func testRetryTappedTriggersReverification() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "a@b.com",
            token: "tok",
            status: .checkFailed,
            reason: .networkError,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
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

    // ONB-002 auth/entitlement migration is future scope — project f946b2b9-0e41-4975-a55a-d5aacc11fcbd

    // MARK: - ONB-002-show_access_unlock_status

    func testActiveStatusSetsIsComplete() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
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

    func testNotActiveStatusShowsReason() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
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

    func testVerifyingStateDuringCheck() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        await store.finish()
    }

    // MARK: - ONB-002-apply_access_unlock_result

    func testApplyVerificationResultTransitionsToActive() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
            status: .notActive,
            reason: .missingInput,
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
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

        XCTAssertEqual(store.state.status, .active)
        XCTAssertTrue(store.state.isComplete)

        await store.finish()
    }

    func testApplyVerificationResultWithExistingCredentials() async {
        let store = TestStore(initialState: BetaAccessFeature.State(
            email: "tester@example.com",
            token: "cbt-token",
        )) {
            BetaAccessFeature()
        } withDependencies: {
            $0.betaAccessClient = BetaAccessClient(verify: { _, _ in
                BetaAccessVerifyResponse(ok: true)
            })
        }

        XCTAssertEqual(store.state.email, "tester@example.com")
        XCTAssertEqual(store.state.token, "cbt-token")

        await store.send(.checkTapped) { state in
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.status = .active
            state.reason = .none
            state.isComplete = true
        }

        XCTAssertEqual(store.state.email, "tester@example.com")
        XCTAssertEqual(store.state.token, "cbt-token")

        await store.finish()
    }
    // swiftlint:enable type_body_length
}

// swiftlint:enable file_length

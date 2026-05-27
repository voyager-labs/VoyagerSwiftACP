@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccess
import XCTest

/*
 ONB-002-present_access_unlock_step reducer 증거 계약

 포함한 interaction_id:
 - ONB-002-show_access_unlock_status: access status snapshot을 활성/비활성 상태로 계산한다.
 - ONB-002-start_access_unlock_recovery: license key와 beta code 입력, retry, mode 전환을 처리한다.
 - ONB-002-apply_access_unlock_result: Core License, beta trial, expired/revoked/network 결과를 unlock 여부와 delegate로 반영한다.

 Fixture reset:
 - `TestStore`와 in-memory `AccessClient`만 사용하므로 영구 credential fixture가 필요 없다.
 */

@MainActor
final class ONB002UnlockAccessReducerTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestStore(
        accessClient: AccessClient = .mock,
    ) -> TestStore<UnlockAccessFeature.State, UnlockAccessFeature.Action> {
        TestStore(initialState: UnlockAccessFeature.State()) {
            UnlockAccessFeature()
        } withDependencies: {
            $0.accessClient = accessClient
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    // MARK: - ONB-002-apply_access_unlock_result

    func testLicenseClaimSuccessEmitsUnlockedDelegate() async {
        let store = makeTestStore()

        await store.send(.licenseKeyChanged("VOYAGER-CORE-VALID")) { state in
            state.licenseKey = "VOYAGER-CORE-VALID"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    // MARK: - Beta Trial Happy Path

    func testBetaTrialSuccessEmitsUnlockedDelegate() async {
        let betaExpiry = Date(timeIntervalSince1970: 1_701_209_600)
        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                redeemBetaCode: { _ in
                    AccessStatusResponse(
                        status: .betaTrialActive,
                        expiresAt: betaExpiry,
                        entitlements: [.betaTrial],
                    )
                },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.claimModeChanged(.betaCode)) { state in
            state.claimMode = .betaCode
        }

        await store.send(.betaCodeChanged("VOYAGER-BETA-TRIAL")) { state in
            state.betaCode = "VOYAGER-BETA-TRIAL"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .betaTrialActive
            state.isComplete = true
            state.trialExpiresAt = betaExpiry
            state.snapshot = AccessStatusSnapshot(
                status: .betaTrialActive,
                expiresAt: betaExpiry,
                entitlements: [.betaTrial],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(store.state.trialExpiresAt, betaExpiry)
        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    func testMissingInputDoesNotSubmit() async {
        let store = makeTestStore()

        await store.send(.submitTapped) { state in
            state.errorMessage = "Please enter a license key or beta code."
        }

        XCTAssertFalse(store.state.isSubmitting)
        await store.finish()
    }

    // MARK: - ONB-002-apply_access_unlock_result

    func testInvalidKeyShowsError() async {
        let store = makeTestStore()

        await store.send(.licenseKeyChanged("INVALID-KEY")) { state in
            state.licenseKey = "INVALID-KEY"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.isComplete = false
            state.errorMessage = "The license key is invalid."
        }

        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    // MARK: - Expired Status

    func testExpiredDoesNotUnlock() async {
        let store = makeTestStore()

        await store.send(.licenseKeyChanged("VOYAGER-EXPIRED")) { state in
            state.licenseKey = "VOYAGER-EXPIRED"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .trialExpired
            state.isComplete = false
            state.errorMessage = "This trial has expired."
            state.snapshot = AccessStatusSnapshot(
                status: .trialExpired,
                entitlements: [],
                fetchedAt: self.referenceDate,
            )
        }

        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    // MARK: - Revoked Status

    func testRevokedDoesNotUnlock() async {
        let store = makeTestStore()

        await store.send(.licenseKeyChanged("VOYAGER-REVOKED")) { state in
            state.licenseKey = "VOYAGER-REVOKED"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .revoked
            state.isComplete = false
            state.errorMessage = "This license has been revoked."
            state.snapshot = AccessStatusSnapshot(
                status: .revoked,
                entitlements: [],
                fetchedAt: self.referenceDate,
            )
        }

        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    // MARK: - Network Failure

    func testNetworkFailureShowsRetry() async {
        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in throw AccessError.networkFailure },
                redeemBetaCode: { _ in throw AccessError.networkFailure },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.licenseKeyChanged("ANY-KEY")) { state in
            state.licenseKey = "ANY-KEY"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .networkFailure
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
        }

        XCTAssertFalse(store.state.isComplete)
        XCTAssertTrue(store.state.showsRetry)

        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    func testRetryAfterFailure() async {
        nonisolated(unsafe) var callCount = 0
        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    callCount += 1
                    if callCount == 1 {
                        throw AccessError.networkFailure
                    }
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in throw AccessError.networkFailure },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.licenseKeyChanged("ANY-KEY")) { state in
            state.licenseKey = "ANY-KEY"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .networkFailure
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
        }

        await store.send(.retryTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .coreLicenseActive
            state.isComplete = true
            state.errorMessage = nil
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(store.state.isComplete)
        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    func testModeSwitchClearsError() async {
        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in throw AccessError.networkFailure },
                redeemBetaCode: { _ in throw AccessError.networkFailure },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.licenseKeyChanged("ANY-KEY")) { state in
            state.licenseKey = "ANY-KEY"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .networkFailure
            state.isComplete = false
            state.errorMessage = "Network error. Please check your connection and try again."
        }

        await store.send(.claimModeChanged(.betaCode)) { state in
            state.claimMode = .betaCode
            state.errorMessage = nil
        }

        XCTAssertNil(store.state.errorMessage)
        await store.finish()
    }

    // MARK: - ONB-002-start_access_unlock_recovery

    func testSubmitUsesLicensePathForLicenseMode() async {
        nonisolated(unsafe) var claimedLicense = false
        nonisolated(unsafe) var redeemedBeta = false

        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    claimedLicense = true
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    redeemedBeta = true
                    return AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.licenseKeyChanged("SOME-KEY")) { state in
            state.licenseKey = "SOME-KEY"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .coreLicenseActive
            state.isComplete = true
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                entitlements: [.coreLicense],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(claimedLicense)
        XCTAssertFalse(redeemedBeta)
        await store.finish()
    }

    func testSubmitUsesBetaPathForBetaMode() async {
        nonisolated(unsafe) var claimedLicense = false
        nonisolated(unsafe) var redeemedBeta = false

        let store = makeTestStore(
            accessClient: AccessClient(
                restoreSession: { nil },
                claimLicense: { _ in
                    claimedLicense = true
                    return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
                },
                redeemBetaCode: { _ in
                    redeemedBeta = true
                    return AccessStatusResponse(status: .betaTrialActive, entitlements: [.betaTrial])
                },
                fetchAccessStatus: { AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense]) },
                signOut: {},
            ),
        )

        await store.send(.claimModeChanged(.betaCode)) { state in
            state.claimMode = .betaCode
        }

        await store.send(.betaCodeChanged("SOME-CODE")) { state in
            state.betaCode = "SOME-CODE"
        }

        await store.send(.submitTapped) { state in
            state.isSubmitting = true
            state.isComplete = false
        }

        await store.receive(\.claimResponse) { state in
            state.isSubmitting = false
            state.status = .betaTrialActive
            state.isComplete = true
            state.snapshot = AccessStatusSnapshot(
                status: .betaTrialActive,
                entitlements: [.betaTrial],
                fetchedAt: self.referenceDate,
            )
        }

        await store.receive(\.delegate.unlocked)

        XCTAssertFalse(claimedLicense)
        XCTAssertTrue(redeemedBeta)
        await store.finish()
    }
}

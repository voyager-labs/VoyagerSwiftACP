import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
extension ACC002CheckEntitlementStatusTests {
    /// ACC-002-check_entitlement_status: binding 완료 시각을 신뢰 복원 증명과 fetch 시각에 함께 기록한다.
    func testDeviceBindingSuccessUsesCompletionTimeForTrustedSnapshotProof() async {
        let fetchDate = Date(timeIntervalSince1970: 1_700_000_000)
        let bindingCompletionDate = fetchDate.addingTimeInterval(1)
        let dates = LockIsolated([fetchDate, bindingCompletionDate])
        let sessionExpiry = fetchDate.addingTimeInterval(3600)
        let periodEnd = fetchDate.addingTimeInterval(7200)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry

        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            )
            $0.date = DateGenerator { dates.withValue { $0.removeFirst() } }
        }

        await store.send(.accessStatusResponse(generation: 1, result: .success(
            AccessStatusResponse(
                hasAccess: true,
                status: "active",
                reason: "active_entitlement",
                productKey: "core",
                currentPeriodEnd: periodEnd,
                source: "polar",
            ),
        ))) { state in
            state.status = .coreLicenseActive
            state.trialExpiresAt = periodEnd
            state.isSubmitting = true
            state.isComplete = false
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }

        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                currentPeriodEnd: periodEnd,
                fetchedAt: bindingCompletionDate,
                sessionExpiresAt: sessionExpiry,
                deviceBindingVerifiedAt: bindingCompletionDate,
            )
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
        }
        await store.receive(\.delegate.unlocked)
    }
}

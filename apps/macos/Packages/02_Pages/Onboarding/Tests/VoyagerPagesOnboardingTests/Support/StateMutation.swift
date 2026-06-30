import Dependencies
import Foundation
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding

// MARK: - 상태 변이 헬퍼

/// 테스트에서 반복 사용하는 상태 변이 패턴을 네임스페이스로 제공합니다.
enum StateMutation {
    static let activeAccessResponse = AccessStatusResponse(
        hasAccess: true,
        status: "active",
        reason: "active_entitlement",
        productKey: "core",
        source: "polar",
    )

    static let activeAccessSnapshot = AccessStatusSnapshot(
        status: .coreLicenseActive,
        fetchedAt: Date(timeIntervalSince1970: 0),
    )

    static let activeAccountSessionClient = AccountSessionClient(
        read: { AccountSession(accessToken: "test-token", status: .coreLicenseActive) },
        persist: { _ in },
        delete: {},
    )

    static let activeAuthNetworkClient = AuthNetworkClient(
        exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
        fetchAccessStatus: { activeAccessResponse },
        refreshToken: { throw AccessError.notConfigured },
    )

    static func installActiveAccessRefresh(_ dependencies: inout DependencyValues) {
        dependencies.accountSessionClient = activeAccountSessionClient
        dependencies.authNetworkClient = activeAuthNetworkClient
        dependencies.accessStatusSnapshotClient = AccessStatusSnapshotClient(
            load: { activeAccessSnapshot },
            save: { _ in },
            remove: {},
        )
        dependencies.date = .constant(activeAccessSnapshot.fetchedAt)
    }

    /// access 상태를 server-canonical active access 결과와 동일하게 설정합니다.
    static func applyActiveAccess(state: inout OnboardingFeature.State) {
        state.accessUnlock.status = .coreLicenseActive
        state.accessUnlock.snapshot = activeAccessSnapshot
        state.accessUnlock.isComplete = true
        state.accessUnlock.isSubmitting = false
    }

    static func applyPersistedCompletedAccessStep(state: inout OnboardingFeature.State) {
        applyActiveAccess(state: &state)
    }

    /// applyStepState + accessSnapshot 복원 경로를 시뮬레이션합니다.
    /// snapshot이 있으면 UnlockAccessFeature.onAppear에서 server-canonical refresh가 트리거됩니다.
    static func applyRestoredBetaAccess(state: inout OnboardingFeature.State) {
        applyPersistedCompletedAccessStep(state: &state)
    }
}

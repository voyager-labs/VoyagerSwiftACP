import Dependencies
import Foundation
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding

// MARK: - 상태 변이 헬퍼

/// 테스트에서 반복 사용하는 상태 변이 패턴을 네임스페이스로 제공합니다.
enum StateMutation {
    static let activeSessionExpiry = Date(timeIntervalSince1970: 4_102_444_800)

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
        sessionExpiresAt: activeSessionExpiry,
        deviceBindingVerifiedAt: Date(timeIntervalSince1970: 0),
    )

    static let activeAccessProjection = OnboardingAccessProjection(
        hasAccountSession: true,
        isComplete: true,
        status: .coreLicenseActive,
        canRefreshAccess: true,
        isBlocked: false,
        primaryCTA: .next,
        snapshot: activeAccessSnapshot,
    )

    static let activeAccountSessionClient = AccountSessionClient(
        read: {
            AccountSession(
                accessToken: "test-token",
                status: .coreLicenseActive,
                expiresAt: activeSessionExpiry,
            )
        },
        persist: { _ in },
        delete: { _ in },
    )

    static let activeAuthNetworkClient = AuthNetworkClient(
        exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
        fetchAccessStatus: { activeAccessResponse },
        bindDevice: { _ in DeviceBindingResponse(ok: true) },
        refreshToken: { throw AccessError.notConfigured },
        syncSession: { _, _ in
            SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .complete,
                accessStatus: activeAccessResponse,
                deviceBindingOutcome: .bound,
                connectedDeviceAvailability: .available,
                sessionExpiresAt: activeSessionExpiry,
            )
        },
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

    static func applyPersistedCompletedAccessStep(state: inout OnboardingFeature.State) {
        state.access = activeAccessProjection
    }
}

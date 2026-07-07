import AppKit
import Combine
@preconcurrency import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

@MainActor
final class ACC001RestoreAccountSessionForegroundObserverTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func makeNotificationCenterClient(
        notifications: @escaping @Sendable (Notification.Name, NSObject?) -> AsyncStream<Notification>,
    ) -> NotificationCenterClient {
        NotificationCenterClient(
            notifications: notifications,
            addObserver: { _, _, _ in NSObject() },
            removeObserver: { _ in },
            publisher: { _ in NotificationCenter.default.publisher(for: .init("")) },
            post: { _, _, _ in },
        )
    }

    private func makeTestStore(
        authNetworkClient: AuthNetworkClient,
        notificationCenterClient: NotificationCenterClient,
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.authNetworkClient = authNetworkClient
            $0.notificationCenterClient = notificationCenterClient
            $0.date = .constant(referenceDate)
        }
    }

    private func sendDidBecomeActive(_ continuation: inout AsyncStream<Notification>.Continuation?) {
        continuation?.yield(Notification(name: NSApplication.didBecomeActiveNotification))
        continuation?.finish()
    }

    private func receiveTrialActiveResponse(
        from store: TestStore<AccountAccessFeature.State, AccountAccessFeature.Action>,
        sessionExpiry: Date,
    ) async {
        await store.receive(\.accessStatusResponse) { state in
            state.status = .trialActive
            state.snapshot = AccessStatusSnapshot(
                status: .trialActive,
                currentPeriodEnd: nil,
                fetchedAt: self.referenceDate,
                sessionExpiresAt: sessionExpiry,
            )
            state.isComplete = true
            state.errorMessage = nil
            state.trialExpiresAt = nil
        }
    }

    func testHydrateLaunchSnapshotWithSessionStartsForegroundObserver() async {
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
        )
        nonisolated(unsafe) var notificationContinuation: AsyncStream<Notification>.Continuation?
        nonisolated(unsafe) var fetchCalled = false

        let store = makeTestStore(
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: {
                    fetchCalled = true
                    return AccessStatusResponse(
                        hasAccess: true,
                        status: "active",
                        reason: "active_entitlement",
                        productKey: "trial",
                        source: "polar",
                    )
                },
                refreshToken: { throw AccessError.notConfigured },
            ),
            notificationCenterClient: Self.makeNotificationCenterClient { _, _ in
                AsyncStream { notificationContinuation = $0 }
            },
        )

        await store.send(.hydrateLaunchSnapshot(snapshot)) { state in
            state.status = snapshot.status
            state.snapshot = snapshot
            state.trialExpiresAt = snapshot.currentPeriodEnd
            state.hasAccountSession = true
            state.sessionExpiresAt = sessionExpiry
            state.isSessionExpired = false
            state.didBootstrap = true
            state.fetchGeneration = 1
            state.ttlTimerActive = true
        }

        await Task.yield()
        sendDidBecomeActive(&notificationContinuation)

        await store.receive(\.appDidBecomeActive) { state in
            state.fetchGeneration = 2
        }

        await receiveTrialActiveResponse(from: store, sessionExpiry: sessionExpiry)
        await store.receive(\.delegate.unlocked)
        XCTAssertTrue(fetchCalled, "foreground notification → fetchAccessStatus 호출")
        await store.skipInFlightEffects()
    }
}

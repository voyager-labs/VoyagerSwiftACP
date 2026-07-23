import AppKit
import Clocks
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
        accountSessionClient: AccountSessionClient,
        authNetworkClient: AuthNetworkClient,
        notificationCenterClient: NotificationCenterClient,
        clock: TestClock<Duration>,
    ) -> TestStore<AccountAccessFeature.State, AccountAccessFeature.Action> {
        TestStore(initialState: AccountAccessFeature.State()) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.notificationCenterClient = notificationCenterClient
            $0.date = .constant(referenceDate)
            $0.continuousClock = clock
        }
    }

    private static func makeAccountSessionClient(expiresAt: Date) -> AccountSessionClient {
        AccountSessionClient(read: { _ in AccountSession(
            accessToken: "test-access-token",
            status: .coreLicenseActive,
            expiresAt: expiresAt,
        )
        }, persist: { _ in },
        delete: { _ in })
    }

    private func makeLaunchSnapshot(sessionExpiry: Date) -> AccessStatusSnapshot {
        AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: referenceDate.addingTimeInterval(86400),
            fetchedAt: referenceDate,
            sessionExpiresAt: sessionExpiry,
        )
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
            state.snapshot = nil
            state.isSubmitting = true
            state.isComplete = false
            state.trialExpiresAt = nil
            state.errorMessage = nil
            state.fetchRetryCount = 0
        }
        await store.receive(\.deviceBindingResponse) { state in
            state.snapshot = AccessStatusSnapshot(
                status: .trialActive,
                currentPeriodEnd: nil,
                fetchedAt: self.referenceDate,
                sessionExpiresAt: sessionExpiry,
                deviceBindingVerifiedAt: self.referenceDate,
            )
            state.isSubmitting = false
            state.isComplete = true
            state.errorMessage = nil
            state.trialExpiresAt = nil
        }
    }

    func testHydrateLaunchSnapshotWithSessionStartsForegroundObserver() async {
        let clock = TestClock()
        let sessionExpiry = referenceDate.addingTimeInterval(3600)
        let snapshot = makeLaunchSnapshot(sessionExpiry: sessionExpiry)
        nonisolated(unsafe) var notificationContinuation: AsyncStream<Notification>.Continuation?
        nonisolated(unsafe) var receivedIntent: SessionSyncIntent?

        let store = makeTestStore(
            accountSessionClient: Self.makeAccountSessionClient(expiresAt: sessionExpiry),
            authNetworkClient: AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in throw DeviceBindingError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: { intent, _ in
                    receivedIntent = intent
                    return SessionSyncResult(
                        sessionStatus: .unchanged,
                        syncStatus: .complete,
                        accessStatus: AccessStatusResponse(hasAccess: true, status: "active"),
                        deviceBindingOutcome: .bound,
                        connectedDeviceAvailability: .available,
                    )
                },
            ),
            notificationCenterClient: Self.makeNotificationCenterClient { _, _ in
                AsyncStream { notificationContinuation = $0 }
            },
            clock: clock,
        )
        store.exhaustivity = .off

        await store.send(.hydrateLaunchSnapshot(snapshot))

        await Task.yield()
        sendDidBecomeActive(&notificationContinuation)

        await store.receive(\.appDidBecomeActive)
        await store.receive(\.revalidatePersistedSession)
        await store.receive(\._persistedSessionRevalidated)
        XCTAssertNil(receivedIntent)
        await store.skipInFlightEffects()
    }
}

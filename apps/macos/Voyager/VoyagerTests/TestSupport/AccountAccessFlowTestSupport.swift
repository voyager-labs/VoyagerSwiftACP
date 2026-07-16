import ComposableArchitecture
import Dependencies
import Foundation
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared

@MainActor
enum AccountAccessFlowTestSupport {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let validSession = AccountSession(
        accessToken: "test-access-token",
        status: .coreLicenseActive,
        refreshToken: "test-refresh-token",
        expiresAt: referenceDate.addingTimeInterval(3600),
    )

    static let expiredSession = AccountSession(
        accessToken: "expired-access-token",
        status: .coreLicenseActive,
        refreshToken: "expired-refresh-token",
        expiresAt: referenceDate.addingTimeInterval(-3600),
    )

    static let loggedOutSession: AccountSession? = nil

    static let successfulSyncResult = SessionSyncResult(
        sessionStatus: .unchanged,
        syncStatus: .complete,
        accessStatus: AccessStatusResponse(
            hasAccess: true,
            status: AccessStatus.coreLicenseActive.rawValue,
            productKey: "core",
        ),
        deviceBindingOutcome: .bound,
        connectedDeviceAvailability: .available,
    )

    static func makeRootStore(
        initialState: AppRootFeature.State = .init(),
        session: AccountSession? = nil,
        exchangeSession: AccountSession = validSession,
        syncResult: SessionSyncResult = successfulSyncResult,
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
        TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in },
                                                           delete: { _ in })
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in exchangeSession },
                fetchAccessStatus: { syncResult.accessStatus },
                refreshToken: { exchangeSession },
                syncSession: { _, _ in syncResult },
            )
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.helperAppClient.terminationEvents = { AsyncStream { $0.finish() } }
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.appHandoffTarget = .voyager
            $0.uuid = .incrementing
            $0.date = .constant(referenceDate)
            $0.continuousClock = TestClock()
        }
    }
}

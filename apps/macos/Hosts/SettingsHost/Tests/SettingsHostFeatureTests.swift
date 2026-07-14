import ComposableArchitecture
@testable import SettingsHost
import VoyagerFeaturesAccountAccess
import VoyagerPagesSettings
import XCTest

final class SettingsHostFeatureTests: XCTestCase {
    @MainActor
    func testSignInDelegateRoutesOnceAndProjectsAccountAccess() async {
        let store = makeStore()

        await store.send(.settings(.delegate(.account(.signInRequested))))
        await store.receive(\.accountAccess.loginTapped) { state in
            state.accountAccess.isSignInInProgress = true
            state.accountAccess.handoffGeneration = 1
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(
                isSignInInProgress: true,
            )
        }
        await store.receive(\.accountAccess.signInHandoffCompleted) { state in
            state.accountAccess.isSignInInProgress = false
            state.accountAccess.didSignInFail = true
            state.accountAccess.errorMessage = "Check your network connection and try again."
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }

        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signInFailed)
        await store.finish()
    }

    @MainActor
    func testConfirmedSignOutDelegateRoutesOnceAndProjectsAccountAccess() async {
        var initialState = SettingsHostState()
        initialState.accountAccess.hasAccountSession = true
        initialState.accountAccess.status = .coreLicenseActive
        initialState.settings = SettingsState(
            accessStatus: .coreLicenseActive,
            accountPresentation: AccountAccessPresentation(
                hasAccountSession: true,
                accessStatus: .coreLicenseActive,
            ),
        )
        let store = makeStore(initialState: initialState)

        await store.send(.settings(.delegate(.account(.signOutRequested))))
        await store.receive(\.accountAccess.signOut) { state in
            state.accountAccess.revalidationGeneration = 1
            state.accountAccess.hasAccountSession = false
            state.accountAccess.isSessionExpired = true
            state.accountAccess.fetchGeneration = 1
            state.accountAccess.syncGeneration = 1
            state.accountAccess.refreshDeadlineGeneration = 1
            state.accountAccess.status = nil
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accessStatus = AccessStatus.none
            state.settings.accountSettings.presentation = AccountAccessPresentation()
        }

        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedOut)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementUnknown)
        await store.receive(\.accountAccess.delegate)
        await store.receive(\.settings.accountAccessPresentationUpdated)
        await store.finish()
    }

    @MainActor
    func testRetryDelegateRoutesOnceAndProjectsAccountAccess() async {
        var initialState = SettingsHostState()
        initialState.accountAccess.hasAccountSession = true
        initialState.accountAccess.status = .networkFailure
        initialState.settings = SettingsState(
            accountPresentation: AccountAccessPresentation(
                hasAccountSession: true,
                accessStatus: .networkFailure,
            ),
        )
        let syncCallCount = LockIsolated(0)
        let store = makeStore(
            initialState: initialState,
            syncSession: { _, _ in
                syncCallCount.withValue { $0 += 1 }
                throw SessionSyncError.capabilityMiss
            },
        )
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.retryRequested))))
        await store.finish()

        XCTAssertEqual(syncCallCount.value, 1)
        XCTAssertFalse(store.state.accountAccess.isSubmitting)
        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedIn)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementUnavailable)
    }

    @MainActor
    func testLiveOnAppearBootstrapsAccountAccessOnlyOnce() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.settings(.onAppear))
        await store.send(.settings(.onAppear))
        await store.skipInFlightEffects()

        XCTAssertFalse(store.state.isAccountAccessBootstrapPending)
        XCTAssertTrue(store.state.accountAccess.didBootstrap)
    }

    @MainActor
    private func makeStore(
        initialState: SettingsHostState = .init(),
        syncSession: @escaping @Sendable (
            SessionSyncIntent,
            DeviceBindingRequest,
        ) async throws -> SessionSyncResult = { _, _ in throw SessionSyncError.capabilityMiss },
    ) -> TestStore<SettingsHostFeature.State, SettingsHostFeature.Action> {
        TestStore(initialState: initialState) {
            SettingsHostFeature()
        } withDependencies: {
            $0.accountSessionClient = .testValue
            $0.accessStatusSnapshotClient = .testValue
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: syncSession,
            )
            $0.signInHandoffClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.defaultFileViewerClient = .previewValue
        }
    }
}

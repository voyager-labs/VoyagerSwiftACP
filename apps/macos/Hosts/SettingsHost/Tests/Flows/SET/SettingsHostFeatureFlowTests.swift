import ComposableArchitecture
@testable import SettingsHost
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
import VoyagerPagesSettings
import VoyagerShared
import XCTest

final class SettingsHostFeatureFlowTests: XCTestCase {
    @MainActor
    func testOnAppearLoadsSandboxHomeBeforeSelectingHome() async {
        let storage = SettingsHostStringStorage()
        let store = makeStore(
            directorySelectionClient: DirectorySelectionClient(
                pickDirectory: { nil },
                pathExists: { _ in true },
                isDirectory: { _ in true },
                standardDirectories: {
                    StandardDirectories(
                        homePath: "/tmp/voyager-settingshost-sandbox",
                        homeDisplayName: "voyager-settingshost-sandbox",
                        desktopPath: nil,
                        documentsPath: nil,
                        downloadsPath: nil,
                    )
                },
            ),
            userDefaultsClient: UserDefaultsClient(
                bool: { _ in false },
                setBool: { _, _ in },
                string: { storage.string(forKey: $0) },
                setString: { storage.setString($0, forKey: $1) },
                double: { _ in 0 },
                setDouble: { _, _ in },
                object: { _ in nil },
                setObject: { _, _ in },
            ),
        )
        store.exhaustivity = .off

        await store.send(.settings(.onAppear))
        await store.send(.settings(.general(.selectDirectoryOption(.home))))
        await store.skipInFlightEffects()

        XCTAssertEqual(
            storage.string(forKey: SettingsKeys.defaultTabPath),
            "/tmp/voyager-settingshost-sandbox",
        )
    }

    @MainActor
    func testSignInDelegateRoutesOnceAndProjectsAccountAccess() async {
        let store = makeStore()

        await store.send(.settings(.delegate(.account(.signInRequested))))
        await store.receive(\.accountAccess.loginTapped) { state in
            state.accountAccess.isSignInInProgress = true
            state.accountAccess.handoffGeneration = 1
            state.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
                context: .paywall,
                scope: .settings,
            )
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
            state.accountAccess.handoffTransaction = nil
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
        initialState.settings = SettingsState(
            accountPresentation: AccountAccessPresentation(
                hasAccountSession: true,
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
            state.settings.accountSettings.presentation = AccountAccessPresentation()
        }

        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedOut)
        await store.finish()
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
        persistedSession: AccountSession? = nil,
        directorySelectionClient: DirectorySelectionClient = .testValue,
        userDefaultsClient: UserDefaultsClient = .testValue,
        syncSession: @escaping @Sendable (
            SessionSyncIntent,
            DeviceBindingRequest,
        ) async throws -> SessionSyncResult = { _, _ in throw SessionSyncError.capabilityMiss },
    ) -> TestStore<SettingsHostFeature.State, SettingsHostFeature.Action> {
        TestStore(initialState: initialState) {
            SettingsHostFeature()
        } withDependencies: {
            $0.accountSessionClient = AccountSessionClient(
                read: { _ in persistedSession },
                persist: { _ in },
                delete: { _ in },
            )
            $0.accessStatusSnapshotClient = .testValue
            $0.date = .constant(.sessionExpiryPast)
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                refreshToken: { throw AccessError.notConfigured },
                syncSession: syncSession,
            )
            $0.signInHandoffClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.defaultFileViewerClient = .previewValue
            $0.directorySelectionClient = directorySelectionClient
            $0.userDefaultsClient = userDefaultsClient
        }
    }
}

private final class SettingsHostStringStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var strings: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.withLock { strings[key] }
    }

    func setString(_ value: String, forKey key: String) {
        lock.withLock { strings[key] = value }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
import VoyagerShared

// MARK: - SettingsHostSandbox

/// Host-mounting sandbox dependency configuration.
///
/// `SettingsHostSandbox`는 `SettingsHostScenario`의 5개 축을 fake/sandbox 의존성 클라이언트로 매핑한다.
/// 기본 sandbox는 프로덕션 app group defaults, keychain, 네트워크, launch-at-login mutation을
/// 절대 건드리지 않는다. 모든 fake 출력은 동일 시나리오에 대해 결정적(deterministic)이다.
///
/// - Note: `date` 의존성은 T0 분류에 따라 `must-remain-real`이므로 fake하지 않는다.
///   호스트 런타임에 실제 clock을 그대로 사용한다.
public enum SettingsHostSandbox {
    private actor SettingsHostAccountAuthBox {
        private var accountAuth: AccountAuthScenario

        init(accountAuth: AccountAuthScenario) {
            self.accountAuth = accountAuth
        }

        func current() -> AccountAuthScenario {
            accountAuth
        }

        func markSignedIn() {
            accountAuth = .signedIn
        }
    }

    public static let suiteName = "group.com.voyager.app.settingshost"

    public static var defaultDependencies: DependencyValues {
        dependencies(for: SettingsHostPreset.defaultSandbox.scenario)
    }

    public static func dependencies(for scenario: SettingsHostScenario) -> DependencyValues {
        var values = DependencyValues()
        configure(&values, for: scenario)
        return values
    }

    public static func configure(
        _ dependencies: inout DependencyValues,
        for scenario: SettingsHostScenario,
    ) {
        let userDefaultsClient = makeUserDefaultsClient(persistence: scenario.persistence)
        let accountAuthBox = SettingsHostAccountAuthBox(accountAuth: scenario.accountAuth)

        dependencies.userDefaultsClient = userDefaultsClient
        dependencies.launchAtLoginClient = .testValue
        dependencies.directorySelectionClient = makeDirectorySelectionClient(permissions: scenario.permissions)
        dependencies.appearanceSettingsClient = makeAppearanceSettingsClient(userDefaultsClient: userDefaultsClient)
        dependencies.collectionSearchAISettingsClient = .live(userDefaultsClient: userDefaultsClient)
        dependencies.aiConnectionsFileClient = makeAIConnectionsFileClient(
            aiConnection: scenario.aiConnection,
            failureLatency: scenario.failureLatency,
        )
        dependencies.aiProviderVerificationClient = makeAIProviderVerificationClient(
            aiConnection: scenario.aiConnection,
            failureLatency: scenario.failureLatency,
        )
        dependencies.aiProviderModelListClient = makeAIProviderModelListClient(
            aiConnection: scenario.aiConnection,
            failureLatency: scenario.failureLatency,
        )
        dependencies.accountSessionClient = makeAccountSessionClient(
            accountAuthBox: accountAuthBox,
            failureLatency: scenario.failureLatency,
        )
        dependencies.accessStatusSnapshotClient = makeAccessStatusSnapshotClient(
            accountAuthBox: accountAuthBox,
            failureLatency: scenario.failureLatency,
            sessionExpiresAt: scenario.sessionExpiresAt,
        )
        dependencies.authNetworkClient = makeAuthNetworkClient(
            accountAuthBox: accountAuthBox,
            failureLatency: scenario.failureLatency,
        )
        dependencies.signInHandoffClient = makeSignInHandoffClient(
            accountAuthBox: accountAuthBox,
            failureLatency: scenario.failureLatency,
        )
        dependencies.checkoutURLClient = .testValue
        dependencies.notificationCenterClient = .testValue
    }

    private static func makeUserDefaultsClient(persistence: PersistenceScenario) -> UserDefaultsClient {
        nonisolated(unsafe) var storage: [String: Any] = [:]
        if persistence == .populated {
            storage[SettingsKeys.theme] = "dark"

            if let data = try? JSONEncoder().encode(CollectionSearchAISettings.default) {
                storage[SettingsKeys.collectionSearchAISettings] = data
            }
        }

        let lock = NSLock()
        return UserDefaultsClient(
            bool: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? Bool ?? false
            },
            setBool: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            string: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? String
            },
            setString: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            double: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key] as? Double ?? 0.0
            },
            setDouble: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
            object: { key in
                lock.lock()
                defer { lock.unlock() }
                return storage[key]
            },
            setObject: { value, key in
                lock.lock()
                defer { lock.unlock() }
                storage[key] = value
            },
        )
    }

    private static func makeAppearanceSettingsClient(userDefaultsClient: UserDefaultsClient)
        -> AppearanceSettingsClient
    {
        AppearanceSettingsClient(
            loadTheme: {
                if let themeString = userDefaultsClient.string(SettingsKeys.theme),
                   let theme = AppTheme(rawValue: themeString)
                {
                    return theme
                }
                return .system
            },
            applyTheme: { _ in },
            applyThemeSync: { _ in },
        )
    }

    private static func makeDirectorySelectionClient(permissions: PermissionScenario) -> DirectorySelectionClient {
        switch permissions {
        case .allGranted:
            DirectorySelectionClient(
                pickDirectory: { "/tmp/voyager-settingshost-sandbox" },
                pathExists: { _ in true },
                isDirectory: { _ in true },
                defaultHomePath: { "/tmp/voyager-settingshost-sandbox" },
            )
        case .denied:
            DirectorySelectionClient(
                pickDirectory: { nil },
                pathExists: { _ in false },
                isDirectory: { _ in false },
                defaultHomePath: { "/tmp/voyager-settingshost-sandbox" },
            )
        }
    }

    private static func makeAccountSessionClient(
        accountAuthBox: SettingsHostAccountAuthBox,
        failureLatency: FailureLatencyScenario,
    ) -> AccountSessionClient {
        AccountSessionClient(
            read: {
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                switch accountAuth {
                case .signedOut, .loading:
                    return nil
                case .signedIn:
                    return AccountSession(
                        accessToken: "sandbox-signed-in-token",
                        status: .coreLicenseActive,
                        refreshToken: "sandbox-refresh-token",
                        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                    )
                case .authExpired:
                    return AccountSession(
                        accessToken: "sandbox-expired-token",
                        status: .none,
                        refreshToken: "sandbox-refresh-token",
                        expiresAt: Date(timeIntervalSince1970: -1),
                    )
                case .error:
                    throw AccessError.networkFailure
                }
            },
            persist: { _ in
                await maybeDelay(failureLatency)
            },
            delete: { _ in
                await maybeDelay(failureLatency)
            },
        )
    }

    private static func makeAccessStatusSnapshotClient(
        accountAuthBox: SettingsHostAccountAuthBox,
        failureLatency: FailureLatencyScenario,
        sessionExpiresAt: Date?,
    ) -> AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(
            load: {
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                switch accountAuth {
                case .signedOut, .loading, .error:
                    return nil
                case .signedIn:
                    return AccessStatusSnapshot(
                        status: .coreLicenseActive,
                        currentPeriodEnd: Date(timeIntervalSince1970: 1_800_000_000),
                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        sessionExpiresAt: sessionExpiresAt,
                        deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    )
                case .authExpired:
                    return AccessStatusSnapshot(
                        status: .trialExpired,
                        currentPeriodEnd: Date(timeIntervalSince1970: -1),
                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        sessionExpiresAt: sessionExpiresAt,
                    )
                }
            },
            save: { _ in
                await maybeDelay(failureLatency)
            },
            remove: {
                await maybeDelay(failureLatency)
            },
        )
    }

    private static func makeAuthNetworkClient(
        accountAuthBox: SettingsHostAccountAuthBox,
        failureLatency: FailureLatencyScenario,
    ) -> AuthNetworkClient {
        AuthNetworkClient(
            exchangeHandoff: { _, _, _ in
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxSession(for: accountAuth)
            },
            fetchAccessStatus: {
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxAccessStatusResponse(for: accountAuth)
            },
            bindDevice: { _ in
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                if accountAuth == .error || failureLatency == .error {
                    throw DeviceBindingError.networkFailure
                }
                return DeviceBindingResponse(ok: true)
            },
            refreshToken: {
                await maybeDelay(failureLatency)
                let accountAuth = await accountAuthBox.current()
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxSession(for: accountAuth)
            },
        )
    }

    private static func makeSignInHandoffClient(
        accountAuthBox: SettingsHostAccountAuthBox,
        failureLatency: FailureLatencyScenario,
    ) -> SignInHandoffClient {
        SignInHandoffClient { _ in
            await maybeDelay(failureLatency)
            let accountAuth = await accountAuthBox.current()
            if accountAuth == .error || failureLatency == .error {
                return .failure
            }
            await accountAuthBox.markSignedIn()
            guard let callbackURL = URL(string: "voyager://auth/callback") else {
                return .failure
            }
            return .success(callbackURL: callbackURL)
        }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
import VoyagerPagesSettings
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
        dependencies.userDefaultsClient = userDefaultsClient
        dependencies.launchAtLoginClient = .testValue
        dependencies.directorySelectionClient = makeDirectorySelectionClient(permissions: scenario.permissions)
        dependencies.defaultFileViewerClient = .previewValue
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
        dependencies.checkoutURLClient = .testValue
        dependencies.notificationCenterClient = .testValue
        dependencies.accountSessionClient = .testValue
        dependencies.accessStatusSnapshotClient = .testValue
        dependencies.authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            refreshToken: { throw AccessError.notConfigured },
            syncSession: { _, _ in throw SessionSyncError.upstream(0) },
        )
        dependencies.signInHandoffClient = .testValue
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
}

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
            accountAuth: scenario.accountAuth,
            failureLatency: scenario.failureLatency,
        )
        dependencies.accessStatusSnapshotClient = makeAccessStatusSnapshotClient(
            accountAuth: scenario.accountAuth,
            failureLatency: scenario.failureLatency,
        )
        dependencies.authNetworkClient = makeAuthNetworkClient(
            accountAuth: scenario.accountAuth,
            failureLatency: scenario.failureLatency,
        )
        dependencies.signInHandoffClient = makeSignInHandoffClient(accountAuth: scenario.accountAuth)
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
        accountAuth: AccountAuthScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AccountSessionClient {
        AccountSessionClient(
            read: {
                await maybeDelay(failureLatency)
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
        accountAuth: AccountAuthScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(
            load: {
                await maybeDelay(failureLatency)
                switch accountAuth {
                case .signedOut, .loading, .error:
                    return nil
                case .signedIn:
                    return AccessStatusSnapshot(
                        status: .coreLicenseActive,
                        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                        entitlements: [],
                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    )
                case .authExpired:
                    return AccessStatusSnapshot(
                        status: .trialExpired,
                        expiresAt: Date(timeIntervalSince1970: -1),
                        entitlements: [],
                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
        accountAuth: AccountAuthScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AuthNetworkClient {
        AuthNetworkClient(
            exchangeHandoff: { _, _, _ in
                await maybeDelay(failureLatency)
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxSession(for: accountAuth)
            },
            fetchAccessStatus: {
                await maybeDelay(failureLatency)
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxAccessStatusResponse(for: accountAuth)
            },
            refreshToken: {
                await maybeDelay(failureLatency)
                if accountAuth == .error || failureLatency == .error {
                    throw AccessError.networkFailure
                }
                return sandboxSession(for: accountAuth)
            },
        )
    }

    private static func makeSignInHandoffClient(accountAuth: AccountAuthScenario) -> SignInHandoffClient {
        SignInHandoffClient {
            switch accountAuth {
            case .signedIn:
                .success(callbackURL: URL(string: "https://example.invalid/settingshost/signin")!)
            case .signedOut, .authExpired, .loading, .error:
                .failure
            }
        }
    }

    private static func makeAIConnectionsFileClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: {
                await maybeDelay(failureLatency)
                if failureLatency == .error {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }

                switch aiConnection {
                case .notConfigured:
                    return .empty()
                case .connected:
                    return sandboxConnectionsFile()
                case .connectionError:
                    return sandboxConnectionsFile()
                }
            },
            save: { file in
                await maybeDelay(failureLatency)
                if failureLatency == .error || aiConnection == .connectionError {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }
                return .success(file)
            },
            deleteCredential: { _ in
                await maybeDelay(failureLatency)
                if failureLatency == .error || aiConnection == .connectionError {
                    throw AiConnectionStoreError.fileSystemError("sandbox failure")
                }
                return .success(.empty())
            },
        )
    }

    private static func makeAIProviderVerificationClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AIProviderVerificationClient {
        AIProviderVerificationClient(
            verify: { _, _ in
                await maybeDelay(failureLatency)
                if aiConnection == .connectionError || failureLatency == .error {
                    return .networkError
                }
                switch aiConnection {
                case .notConfigured:
                    return .unsupportedProvider
                case .connected:
                    return .valid
                case .connectionError:
                    return .invalid(.verificationFailed)
                }
            },
        )
    }

    private static func makeAIProviderModelListClient(
        aiConnection: AIConnectionScenario,
        failureLatency: FailureLatencyScenario,
    ) -> AiProviderModelListClient {
        AiProviderModelListClient(
            loadModels: { provider, _ in
                await maybeDelay(failureLatency)
                if aiConnection == .connectionError || failureLatency == .error {
                    throw AiProviderModelListError.networkError(
                        provider: provider,
                        description: "sandbox connection error",
                    )
                }

                switch aiConnection {
                case .notConfigured:
                    throw AiProviderModelListError.unsupportedProvider(provider)
                case .connected:
                    return sandboxModels(for: provider)
                case .connectionError:
                    throw AiProviderModelListError.networkError(
                        provider: provider,
                        description: "sandbox connection error",
                    )
                }
            },
        )
    }

    private static func sandboxConnectionsFile() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 1_700_000_000_123,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sandbox-openai-secret")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected, lastVerifiedAtMs: 1_700_000_000_456),
                ),
            ],
        )
    }

    private static func sandboxModels(for provider: AiProvider) -> [AiProviderModel] {
        switch provider {
        case .openai:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .openai, rawValue: "gpt-4.1"),
                    provider: .openai,
                    rawModelID: "gpt-4.1",
                    displayName: "GPT-4.1",
                    providerDisplayName: "OpenAI",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        case .chatgptCodex:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .chatgptCodex, rawValue: "codex-sandbox"),
                    provider: .chatgptCodex,
                    rawModelID: "codex-sandbox",
                    displayName: "Codex Sandbox",
                    providerDisplayName: "ChatGPT Codex",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        case .anthropic:
            [
                AiProviderModel(
                    id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-sandbox"),
                    provider: .anthropic,
                    rawModelID: "claude-sonnet-sandbox",
                    displayName: "Claude Sonnet Sandbox",
                    providerDisplayName: "Anthropic",
                    thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "sandbox")),
                ),
            ]
        }
    }

    private static func sandboxSession(for accountAuth: AccountAuthScenario) -> AccountSession {
        switch accountAuth {
        case .signedIn:
            AccountSession(
                accessToken: "sandbox-signed-in-token",
                status: .coreLicenseActive,
                refreshToken: "sandbox-refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            )
        case .authExpired:
            AccountSession(
                accessToken: "sandbox-expired-token",
                status: .none,
                refreshToken: "sandbox-refresh-token",
                expiresAt: Date(timeIntervalSince1970: -1),
            )
        case .signedOut, .loading, .error:
            AccountSession(
                accessToken: "sandbox-empty-token",
                status: .none,
                refreshToken: nil,
                expiresAt: nil,
            )
        }
    }

    private static func sandboxAccessStatusResponse(for accountAuth: AccountAuthScenario) -> AccessStatusResponse {
        switch accountAuth {
        case .signedIn:
            AccessStatusResponse(
                status: .coreLicenseActive,
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                entitlements: [],
                message: nil,
                reasonCode: nil,
            )
        case .authExpired:
            AccessStatusResponse(
                status: .trialExpired,
                expiresAt: Date(timeIntervalSince1970: -1),
                entitlements: [],
                message: "sandbox session lapse",
                reasonCode: "session_lapse",
            )
        case .signedOut, .loading, .error:
            AccessStatusResponse(
                status: .none,
                expiresAt: nil,
                entitlements: [],
                message: nil,
                reasonCode: nil,
            )
        }
    }

    private static func maybeDelay(_ failureLatency: FailureLatencyScenario) async {
        guard failureLatency == .latency else { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

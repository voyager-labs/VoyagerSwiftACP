import ComposableArchitecture
import Foundation

public enum AiProviderConnectionError: Error, Equatable, Sendable {
    case unsupportedProvider
    case invalidCredential
    case storeError(AiConnectionStoreError)
    case verificationFailed(ProviderStatusReason)
}

public struct AiProviderConnectionResult: Equatable, Sendable {
    public let provider: AiProvider
    public let state: ProviderConnectionState
    public let reason: ProviderStatusReason
    public let updatedFile: AIConnectionsFile

    public init(
        provider: AiProvider,
        state: ProviderConnectionState,
        reason: ProviderStatusReason,
        updatedFile: AIConnectionsFile,
    ) {
        self.provider = provider
        self.state = state
        self.reason = reason
        self.updatedFile = updatedFile
    }
}

/// A dependency client that manages AI provider connection lifecycle (connect via OAuth, connect via API key,
/// disconnect).
///
/// Verification ownership lives in the reducer (via `AIProviderVerificationClient`).
/// This client is a **persistence-only** layer: it validates auth-method compatibility,
/// writes credentials, and returns the updated file. It does NOT perform runtime verification.
public struct AIProviderConnectionClient: Sendable {
    public var connectOAuth: @Sendable (AiProvider, OAuthCredentialFile, ProviderConnectionState) async
        -> AiProviderConnectionResult
    public var connectAPIKey: @Sendable (AiProvider, String, ProviderConnectionState) async
        -> AiProviderConnectionResult
    public var disconnect: @Sendable (AiProvider) async -> AiProviderConnectionResult

    public nonisolated init(
        connectOAuth: @escaping @Sendable (AiProvider, OAuthCredentialFile, ProviderConnectionState) async
            -> AiProviderConnectionResult,
        connectAPIKey: @escaping @Sendable (AiProvider, String, ProviderConnectionState) async
            -> AiProviderConnectionResult,
        disconnect: @escaping @Sendable (AiProvider) async -> AiProviderConnectionResult,
    ) {
        self.connectOAuth = connectOAuth
        self.connectAPIKey = connectAPIKey
        self.disconnect = disconnect
    }
}

extension AIProviderConnectionClient: DependencyKey {
    public nonisolated static var liveValue: AIProviderConnectionClient {
        let store = AIConnectionFileStore.withDefaultHome()
        return Self.persistenceClient(store: store)
    }

    public nonisolated static func liveForRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default,
    ) -> AIProviderConnectionClient {
        let store = AIConnectionFileStore.withRepoRoot(
            repoRootURL: repoRootURL,
            fileManager: fileManager,
        )
        return Self.persistenceClient(store: store)
    }

    private nonisolated static func persistenceClient(
        store: AIConnectionFileStore,
    ) -> AIProviderConnectionClient {
        AIProviderConnectionClient(
            connectOAuth: connectOAuthHandler(store: store),
            connectAPIKey: connectAPIKeyHandler(store: store),
            disconnect: disconnectHandler(store: store),
        )
    }

    private nonisolated static func connectOAuthHandler(
        store: AIConnectionFileStore,
    ) -> @Sendable (AiProvider, OAuthCredentialFile, ProviderConnectionState) async -> AiProviderConnectionResult {
        { provider, credential, connectionState in
            try? await store.migrateFromHomeIfNeeded()
            guard let descriptor = ProviderDescriptor.descriptor(for: provider),
                  descriptor.authMethod == .oauth
            else {
                return unsupportedProviderResult(provider: provider)
            }

            let credentialPayload = StoredCredentialPayload.oauth(credential)
            let reason: ProviderStatusReason = connectionState == .notVerified ? .networkUnavailable : .none
            return await Self.persistAndReturn(
                store: store,
                provider: provider,
                authMethod: descriptor.authMethod,
                credential: credentialPayload,
                connectionState: connectionState,
                reason: reason,
            )
        }
    }

    private nonisolated static func connectAPIKeyHandler(
        store: AIConnectionFileStore,
    ) -> @Sendable (AiProvider, String, ProviderConnectionState) async -> AiProviderConnectionResult {
        { provider, secret, connectionState in
            try? await store.migrateFromHomeIfNeeded()
            guard let descriptor = ProviderDescriptor.descriptor(for: provider),
                  descriptor.authMethod == .apiKey
            else {
                return unsupportedProviderResult(provider: provider)
            }

            let credentialPayload = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: secret))
            let reason: ProviderStatusReason = connectionState == .notVerified ? .networkUnavailable : .none
            return await Self.persistAndReturn(
                store: store,
                provider: provider,
                authMethod: descriptor.authMethod,
                credential: credentialPayload,
                connectionState: connectionState,
                reason: reason,
            )
        }
    }

    private nonisolated static func disconnectHandler(
        store: AIConnectionFileStore,
    ) -> @Sendable (AiProvider) async -> AiProviderConnectionResult {
        { provider in
            do {
                try await store.migrateFromHomeIfNeeded()
                try await store.deleteCredential(for: provider)
            } catch {
                let current = await (try? store.load()) ?? AIConnectionsFile.empty()
                return AiProviderConnectionResult(
                    provider: provider,
                    state: .connectionFailed,
                    reason: .unknown,
                    updatedFile: current,
                )
            }
            let updated = await (try? store.load()) ?? AIConnectionsFile.empty()

            return AiProviderConnectionResult(
                provider: provider,
                state: .notVerified,
                reason: .none,
                updatedFile: updated,
            )
        }
    }

    private nonisolated static func unsupportedProviderResult(provider: AiProvider) -> AiProviderConnectionResult {
        AiProviderConnectionResult(
            provider: provider,
            state: .connectionFailed,
            reason: .providerUnsupportedInBuild,
            updatedFile: AIConnectionsFile.empty(),
        )
    }

    private nonisolated static func persistAndReturn(
        store: AIConnectionFileStore,
        provider: AiProvider,
        authMethod: ProviderAuthMethod,
        credential: StoredCredentialPayload,
        connectionState: ProviderConnectionState,
        reason: ProviderStatusReason,
    ) async -> AiProviderConnectionResult {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let record = providerRecord(
            provider: provider,
            authMethod: authMethod,
            credential: credential,
            connectionState: connectionState,
            reason: reason,
            now: now,
        )

        do {
            let updated = try await store.update { current in
                Self.updatedConnectionsFile(
                    current: current,
                    provider: provider,
                    record: record,
                    now: now,
                )
            }
            return AiProviderConnectionResult(
                provider: provider,
                state: connectionState,
                reason: reason,
                updatedFile: updated,
            )
        } catch {
            let current = await (try? store.load()) ?? AIConnectionsFile.empty()
            return AiProviderConnectionResult(
                provider: provider,
                state: .connectionFailed,
                reason: .unknown,
                updatedFile: current,
            )
        }
    }

    private nonisolated static func providerRecord(
        provider: AiProvider,
        authMethod: ProviderAuthMethod,
        credential: StoredCredentialPayload,
        connectionState: ProviderConnectionState,
        reason: ProviderStatusReason,
        now: Int64,
    ) -> ProviderRecordFile {
        let snapshotReason: ProviderStatusReason = connectionState == .connected ? .none : reason
        return ProviderRecordFile(
            providerId: provider,
            authMethod: authMethod,
            credential: credential,
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: connectionState,
                lastVerifiedAtMs: connectionState == .connected ? now : nil,
                lastErrorCode: snapshotReason,
            ),
        )
    }

    private nonisolated static func updatedConnectionsFile(
        current: AIConnectionsFile,
        provider: AiProvider,
        record: ProviderRecordFile,
        now: Int64,
    ) -> AIConnectionsFile {
        var providers = current.providers
        providers[provider.rawValue] = record

        return AIConnectionsFile(
            schemaVersion: current.schemaVersion,
            updatedAtMs: now,
            lastUsedProviderId: provider,
            lastUsedAtMs: now,
            providers: providers,
        )
    }

    public nonisolated static var testValue: AIProviderConnectionClient {
        AIProviderConnectionClient(
            connectOAuth: { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
            connectAPIKey: { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
            disconnect: { provider in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .notVerified,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
        )
    }

    public nonisolated static var previewValue: AIProviderConnectionClient {
        AIProviderConnectionClient(
            connectOAuth: { provider, _, _ in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .connected,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
            connectAPIKey: { provider, _, _ in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .connected,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
            disconnect: { provider in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .notVerified,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiProviderConnectionClient: AIProviderConnectionClient {
        get { self[AIProviderConnectionClient.self] }
        set { self[AIProviderConnectionClient.self] = newValue }
    }
}

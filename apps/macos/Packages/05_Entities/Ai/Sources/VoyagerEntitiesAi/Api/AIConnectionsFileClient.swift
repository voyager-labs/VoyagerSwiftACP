import ComposableArchitecture
import Foundation

public enum AiConnectionStoreError: Error, Equatable, Sendable {
    case fileSystemError(String)
    case lockContention
    case quarantineRecovery
}

public enum AiConnectionMutationResult: Equatable, Sendable {
    case success(AIConnectionsFile)
    case partialSuccess(AIConnectionsFile, failedProviders: [AiProvider])
    case fileSystemError(AiConnectionStoreError)
}

public struct AIConnectionsFileClient: Sendable {
    public var load: @Sendable () async throws -> AIConnectionsFile
    public var save: @Sendable (AIConnectionsFile) async throws -> AiConnectionMutationResult
    public var deleteCredential: @Sendable (AiProvider) async throws -> AiConnectionMutationResult

    public nonisolated init(
        load: @escaping @Sendable () async throws -> AIConnectionsFile,
        save: @escaping @Sendable (AIConnectionsFile) async throws -> AiConnectionMutationResult,
        deleteCredential: @escaping @Sendable (AiProvider) async throws -> AiConnectionMutationResult,
    ) {
        self.load = load
        self.save = save
        self.deleteCredential = deleteCredential
    }
}

extension AIConnectionsFileClient: DependencyKey {
    public nonisolated static var liveValue: AIConnectionsFileClient {
        let store = AIConnectionFileStore.withDefaultHome()

        return AIConnectionsFileClient(
            load: {
                try await store.migrateFromHomeIfNeeded()
                return try await store.load()
            },
            save: { file in
                do {
                    try await store.migrateFromHomeIfNeeded()
                    try await store.write(file)
                    return .success(file)
                } catch _ as POSIXLockError {
                    return .fileSystemError(.lockContention)
                } catch {
                    return .fileSystemError(.fileSystemError(error.localizedDescription))
                }
            },
            deleteCredential: { provider in
                do {
                    try await store.migrateFromHomeIfNeeded()
                    try await store.deleteCredential(for: provider)
                    let updated = try await store.load()
                    return .success(updated)
                } catch _ as POSIXLockError {
                    return .fileSystemError(.lockContention)
                } catch {
                    return .fileSystemError(.fileSystemError(error.localizedDescription))
                }
            },
        )
    }

    public nonisolated static func liveForRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default,
    ) -> AIConnectionsFileClient {
        let store = AIConnectionFileStore.withRepoRoot(
            repoRootURL: repoRootURL,
            fileManager: fileManager,
        )

        return AIConnectionsFileClient(
            load: { try await store.load() },
            save: { file in
                do {
                    try await store.write(file)
                    return .success(file)
                } catch _ as POSIXLockError {
                    return .fileSystemError(.lockContention)
                } catch {
                    return .fileSystemError(.fileSystemError(error.localizedDescription))
                }
            },
            deleteCredential: { provider in
                do {
                    try await store.deleteCredential(for: provider)
                    let updated = try await store.load()
                    return .success(updated)
                } catch _ as POSIXLockError {
                    return .fileSystemError(.lockContention)
                } catch {
                    return .fileSystemError(.fileSystemError(error.localizedDescription))
                }
            },
        )
    }

    public nonisolated static var testValue: AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: { AIConnectionsFile.empty() },
            save: { .success($0) },
            deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
        )
    }

    public nonisolated static var previewValue: AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: {
                AIConnectionsFile(
                    updatedAtMs: 1_760_000_000_000,
                    providers: [
                        "openai": ProviderRecordFile(
                            providerId: .openai,
                            authMethod: .apiKey,
                            credential: .apiKey(APIKeyCredentialFile(secret: "sk-preview")),
                            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                        ),
                    ],
                )
            },
            save: { .success($0) },
            deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
        )
    }
}

public extension DependencyValues {
    nonisolated var aiConnectionsFileClient: AIConnectionsFileClient {
        get { self[AIConnectionsFileClient.self] }
        set { self[AIConnectionsFileClient.self] = newValue }
    }
}

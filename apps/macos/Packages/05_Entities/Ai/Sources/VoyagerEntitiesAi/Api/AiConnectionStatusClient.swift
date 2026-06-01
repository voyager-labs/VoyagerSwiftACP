import ComposableArchitecture
import Foundation

public enum AIConnectionStatus: Equatable, Sendable {
    case ready
    case notConfigured
    case invalidCredential(ProviderStatusReason)
    case networkUnavailable
    case verificationFailed
}

public struct AiConnectionStatusClient: Sendable {
    public var checkStatus: @Sendable (AiProvider) async -> AIConnectionStatus

    public nonisolated init(
        checkStatus: @escaping @Sendable (AiProvider) async -> AIConnectionStatus,
    ) {
        self.checkStatus = checkStatus
    }
}

extension AiConnectionStatusClient: DependencyKey {
    public nonisolated static var liveValue: AiConnectionStatusClient {
        let store = AIConnectionFileStore.withDefaultHome()
        return persistenceClient(store: store)
    }

    public nonisolated static func liveForRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default,
    ) -> AiConnectionStatusClient {
        let store = AIConnectionFileStore.withRepoRoot(
            repoRootURL: repoRootURL,
            fileManager: fileManager,
        )
        return persistenceClient(store: store)
    }

    private nonisolated static func persistenceClient(store: AIConnectionFileStore) -> AiConnectionStatusClient {
        let runtimeClient = AiConnectionRuntimeClient.live()
        return AiConnectionStatusClient(
            checkStatus: { provider in
                try? await store.migrateFromHomeIfNeeded()
                let file = await (try? store.load()) ?? AIConnectionsFile.empty()
                guard let record = file.providers[provider.rawValue],
                      record.credential != nil
                else {
                    return .notConfigured
                }
                if record.snapshot.lastKnownStatus == .connected {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    return Self.status(from: result)
                }
                return Self.status(from: record.snapshot)
            },
        )
    }

    private nonisolated static func status(from result: AiProviderVerificationResult) -> AIConnectionStatus {
        switch result {
        case .valid:
            .ready
        case let .invalid(reason):
            .invalidCredential(reason)
        case .networkError:
            .networkUnavailable
        case .unsupportedProvider:
            .verificationFailed
        }
    }

    private nonisolated static func status(from snapshot: ProviderSnapshotFile) -> AIConnectionStatus {
        switch snapshot.lastKnownStatus {
        case .connected:
            .ready
        case .connectionFailed:
            .invalidCredential(snapshot.lastErrorCode)
        case .notVerified:
            .notConfigured
        default:
            .notConfigured
        }
    }

    public nonisolated static var testValue: AiConnectionStatusClient {
        AiConnectionStatusClient(checkStatus: { _ in .ready })
    }

    public nonisolated static var previewValue: AiConnectionStatusClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var aiConnectionStatusClient: AiConnectionStatusClient {
        get { self[AiConnectionStatusClient.self] }
        set { self[AiConnectionStatusClient.self] = newValue }
    }
}

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

    nonisolated public init(
        checkStatus: @escaping @Sendable (AiProvider) async -> AIConnectionStatus,
    ) {
        self.checkStatus = checkStatus
    }
}

extension AiConnectionStatusClient: DependencyKey {
    nonisolated public static var liveValue: AiConnectionStatusClient {
        let store = AIConnectionFileStore.withDefaultHome()
        return persistenceClient(store: store)
    }

    nonisolated public static func liveForRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default,
    ) -> AiConnectionStatusClient {
        let store = AIConnectionFileStore.withRepoRoot(
            repoRootURL: repoRootURL,
            fileManager: fileManager,
        )
        return persistenceClient(store: store)
    }

    nonisolated static func persistenceClient(
        store: AIConnectionFileStore,
        runtimeClient: AiConnectionRuntimeClient = .live(),
    ) -> AiConnectionStatusClient {
        AiConnectionStatusClient(
            checkStatus: { provider in
                try? await store.migrateFromHomeIfNeeded()
                if provider == .chatgptCodex {
                    _ = try? await store.update { AIConnectionsNormalizer.normalize($0) }
                }
                let file = await (try? store.load()) ?? AIConnectionsFile.empty()
                guard let record = file.providers[provider.rawValue] else {
                    return .notConfigured
                }
                if provider == .chatgptCodex {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    return Self.status(from: result)
                }
                guard record.credential != nil else { return .notConfigured }
                if record.snapshot.lastKnownStatus == .connected {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    return Self.status(from: result)
                }
                return Self.status(from: record.snapshot)
            },
        )
    }

    nonisolated private static func status(from result: AiProviderVerificationResult) -> AIConnectionStatus {
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

    nonisolated private static func status(from snapshot: ProviderSnapshotFile) -> AIConnectionStatus {
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

    nonisolated public static var testValue: AiConnectionStatusClient {
        AiConnectionStatusClient(checkStatus: { _ in .ready })
    }

    nonisolated public static var previewValue: AiConnectionStatusClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var aiConnectionStatusClient: AiConnectionStatusClient {
        get { self[AiConnectionStatusClient.self] }
        set { self[AiConnectionStatusClient.self] = newValue }
    }
}

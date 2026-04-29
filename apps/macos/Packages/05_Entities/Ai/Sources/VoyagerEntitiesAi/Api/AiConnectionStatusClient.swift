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
        checkStatus: @escaping @Sendable (AiProvider) async -> AIConnectionStatus
    ) {
        self.checkStatus = checkStatus
    }
}

extension AiConnectionStatusClient: DependencyKey {
    public nonisolated static var liveValue: AiConnectionStatusClient {
        let store = AIConnectionFileStore.withDefaultHome()
        let runtimeClient = AiConnectionRuntimeClient.live()

        return AiConnectionStatusClient(
            checkStatus: { provider in
                try? await store.migrateFromHomeIfNeeded()
                let file = await (try? store.load()) ?? AIConnectionsFile.empty()
                guard let record = file.providers[provider.rawValue] else {
                    return .notConfigured
                }
                guard record.credential != nil else {
                    return .notConfigured
                }
                if record.snapshot.lastKnownStatus == .connected {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    switch result {
                    case .valid:
                        return .ready
                    case let .invalid(reason):
                        return .invalidCredential(reason)
                    case .networkError:
                        return .networkUnavailable
                    case .unsupportedProvider:
                        return .verificationFailed
                    }
                }
                switch record.snapshot.lastKnownStatus {
                case .connected:
                    return .ready
                case .connectionFailed:
                    return .invalidCredential(record.snapshot.lastErrorCode)
                case .notVerified:
                    return .notConfigured
                default:
                    return .notConfigured
                }
            }
        )
    }

    public nonisolated static func liveForRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default
    ) -> AiConnectionStatusClient {
        let store = AIConnectionFileStore.withRepoRoot(
            fileManager: fileManager,
            repoRootURL: repoRootURL
        )
        let runtimeClient = AiConnectionRuntimeClient.live()

        return AiConnectionStatusClient(
            checkStatus: { provider in
                try? await store.migrateFromHomeIfNeeded()
                let file = await (try? store.load()) ?? AIConnectionsFile.empty()
                guard let record = file.providers[provider.rawValue] else {
                    return .notConfigured
                }
                guard record.credential != nil else {
                    return .notConfigured
                }
                if record.snapshot.lastKnownStatus == .connected {
                    let result = await runtimeClient.verifyProvider(provider, record.credential)
                    switch result {
                    case .valid:
                        return .ready
                    case let .invalid(reason):
                        return .invalidCredential(reason)
                    case .networkError:
                        return .networkUnavailable
                    case .unsupportedProvider:
                        return .verificationFailed
                    }
                }
                switch record.snapshot.lastKnownStatus {
                case .connected:
                    return .ready
                case .connectionFailed:
                    return .invalidCredential(record.snapshot.lastErrorCode)
                case .notVerified:
                    return .notConfigured
                default:
                    return .notConfigured
                }
            }
        )
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

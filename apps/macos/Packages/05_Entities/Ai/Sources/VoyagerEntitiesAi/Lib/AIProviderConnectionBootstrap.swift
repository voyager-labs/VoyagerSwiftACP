import Foundation

public struct AIProviderBootstrapResult: Equatable, Sendable {
    public let provider: AiProvider
    public let connectionState: ProviderConnectionState
    public let statusReason: ProviderStatusReason

    public init(
        provider: AiProvider,
        connectionState: ProviderConnectionState,
        statusReason: ProviderStatusReason = .none,
    ) {
        self.provider = provider
        self.connectionState = connectionState
        self.statusReason = statusReason
    }
}

public enum AIProviderConnectionBootstrap {
    public static func initialResults(from file: AIConnectionsFile) -> [AIProviderBootstrapResult] {
        ProviderDescriptor.v1Catalog.map { descriptor in
            let record = file.providers[descriptor.provider.rawValue]
            return initialResult(for: descriptor.provider, record: record)
        }
    }

    public static func initialResult(
        for provider: AiProvider,
        record: ProviderRecordFile?,
    ) -> AIProviderBootstrapResult {
        guard let record else {
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none,
            )
        }

        guard record.credential != nil else {
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .missingCredential,
            )
        }

        switch record.snapshot.lastKnownStatus {
        case .disconnecting, .disconnected:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .disconnected,
                statusReason: .none,
            )
        case .connectInProgress:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none,
            )
        case .notVerified, .checkingStatus, .connected, .connectionFailed, .unavailable:
            return AIProviderBootstrapResult(
                provider: provider,
                connectionState: .checkingStatus,
                statusReason: .none,
            )
        }
    }

    public static func shouldVerify(snapshotState: ProviderConnectionState) -> Bool {
        switch snapshotState {
        case .connectInProgress, .disconnecting, .disconnected:
            false
        case .notVerified, .checkingStatus, .connected, .connectionFailed, .unavailable:
            true
        }
    }

    public static func verifiedResult(
        for provider: AiProvider,
        verification: AiProviderVerificationResult,
    ) -> AIProviderBootstrapResult {
        switch verification {
        case .valid:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .connected,
                statusReason: .none,
            )
        case let .invalid(reason):
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: reason == .providerUnsupportedInBuild ? .unavailable : .connectionFailed,
                statusReason: reason,
            )
        case .networkError:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .connectionFailed,
                statusReason: .networkUnavailable,
            )
        case .unsupportedProvider:
            AIProviderBootstrapResult(
                provider: provider,
                connectionState: .unavailable,
                statusReason: .providerUnsupportedInBuild,
            )
        }
    }

    public static func updatedConnectionsFile(
        verificationSourceFile: AIConnectionsFile,
        latestFile: AIConnectionsFile,
        applying results: [AIProviderBootstrapResult],
    ) -> AIConnectionsFile? {
        var providers = latestFile.providers
        var didUpdate = false

        for result in results {
            let providerKey = result.provider.rawValue
            guard let sourceRecord = verificationSourceFile.providers[providerKey],
                  var record = providers[providerKey],
                  record.credential != nil,
                  record.credential == sourceRecord.credential
            else { continue }

            let lastErrorCode: ProviderStatusReason = result.connectionState == .connected ? .none : result.statusReason
            guard record.snapshot.lastKnownStatus != result.connectionState
                || record.snapshot.lastErrorCode != lastErrorCode
            else { continue }

            let snapshot = ProviderSnapshotFile(
                lastKnownStatus: result.connectionState,
                lastVerifiedAtMs: result.connectionState == .connected ? latestFile.updatedAtMs : nil,
                lastErrorCode: lastErrorCode,
            )

            record = ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: record.credential,
                snapshot: snapshot,
                provenance: record.provenance,
            )
            providers[providerKey] = record
            didUpdate = true
        }

        guard didUpdate else { return nil }
        return AIConnectionsFile(
            schemaVersion: latestFile.schemaVersion,
            updatedAtMs: latestFile.updatedAtMs,
            lastUsedProviderId: latestFile.lastUsedProviderId,
            lastUsedAtMs: latestFile.lastUsedAtMs,
            providers: providers,
        )
    }
}

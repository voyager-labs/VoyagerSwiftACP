import Foundation

/// Persisted snapshot of a provider's last-known status.
/// Updated after verification, connect, and disconnect flows.
public struct ProviderSnapshotFile: Equatable, Sendable {
    public let lastKnownStatus: ProviderConnectionState
    public let lastVerifiedAtMs: Int64?
    public let lastErrorCode: ProviderStatusReason

    public init(
        lastKnownStatus: ProviderConnectionState,
        lastVerifiedAtMs: Int64? = nil,
        lastErrorCode: ProviderStatusReason = .none,
    ) {
        self.lastKnownStatus = lastKnownStatus
        self.lastVerifiedAtMs = lastVerifiedAtMs
        self.lastErrorCode = lastErrorCode
    }
}

/// A single provider's persisted record in the config file.
/// Contains the provider identity, auth method, optional credential, status snapshot,
/// and optional provenance tracking how the connection was originally established.
public struct ProviderRecordFile: Equatable, Sendable {
    public let providerId: AiProvider
    public let authMethod: ProviderAuthMethod
    public let credential: StoredCredentialPayload?
    public let snapshot: ProviderSnapshotFile
    public let provenance: ProviderConnectPath?

    public init(
        providerId: AiProvider,
        authMethod: ProviderAuthMethod,
        snapshot: ProviderSnapshotFile,
        credential: StoredCredentialPayload? = nil,
        provenance: ProviderConnectPath? = nil,
    ) {
        self.providerId = providerId
        self.authMethod = authMethod
        self.credential = credential
        self.snapshot = snapshot
        self.provenance = provenance
    }

    public init(
        providerId: AiProvider,
        authMethod: ProviderAuthMethod,
        credential: StoredCredentialPayload?,
        snapshot: ProviderSnapshotFile,
        provenance: ProviderConnectPath? = nil,
    ) {
        self.init(
            providerId: providerId,
            authMethod: authMethod,
            snapshot: snapshot,
            credential: credential,
            provenance: provenance,
        )
    }

    public var redacted: ProviderRecordFile {
        ProviderRecordFile(
            providerId: providerId,
            authMethod: authMethod,
            snapshot: snapshot,
            credential: credential?.redacted,
            provenance: provenance,
        )
    }
}

// MARK: - Codable

extension ProviderSnapshotFile: Codable {}
extension ProviderRecordFile: Codable {}

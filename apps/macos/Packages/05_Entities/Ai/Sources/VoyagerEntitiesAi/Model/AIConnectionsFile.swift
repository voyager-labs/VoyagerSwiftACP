import Foundation

/// Top-level persisted schema for all AI provider connections.
/// Stored at `<root>/.voyager/auth.json`.
/// Provider-keyed single connection per provider for v1.
public struct AIConnectionsFile: Equatable, Sendable {
    public let schemaVersion: Int
    public let updatedAtMs: Int64
    public let lastUsedProviderId: AiProvider?
    public let lastUsedAtMs: Int64?
    public let providers: [String: ProviderRecordFile]

    public init(
        schemaVersion: Int = 1,
        updatedAtMs: Int64,
        lastUsedProviderId: AiProvider? = nil,
        lastUsedAtMs: Int64? = nil,
        providers: [String: ProviderRecordFile] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.lastUsedProviderId = lastUsedProviderId
        self.lastUsedAtMs = lastUsedAtMs
        self.providers = providers
    }

    /// Creates an empty file payload for missing-file or reset scenarios.
    public static func empty(updatedAtMs: Int64 = 0) -> AIConnectionsFile {
        AIConnectionsFile(
            schemaVersion: 1,
            updatedAtMs: updatedAtMs,
            providers: [:]
        )
    }

    /// Returns a copy with all provider credentials redacted for safe logging.
    public var redacted: AIConnectionsFile {
        AIConnectionsFile(
            schemaVersion: schemaVersion,
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: lastUsedProviderId,
            lastUsedAtMs: lastUsedAtMs,
            providers: providers.mapValues { $0.redacted }
        )
    }
}

// MARK: - Codable

extension AIConnectionsFile: Codable {}

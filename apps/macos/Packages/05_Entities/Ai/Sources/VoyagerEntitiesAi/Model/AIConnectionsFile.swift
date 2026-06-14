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
        updatedAtMs: Int64,
        schemaVersion: Int = 1,
        lastUsedProviderId: AiProvider? = nil,
        lastUsedAtMs: Int64? = nil,
        providers: [String: ProviderRecordFile] = [:],
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.lastUsedProviderId = lastUsedProviderId
        self.lastUsedAtMs = lastUsedAtMs
        self.providers = providers
    }

    public init(
        schemaVersion: Int,
        updatedAtMs: Int64,
        lastUsedProviderId: AiProvider? = nil,
        lastUsedAtMs: Int64? = nil,
        providers: [String: ProviderRecordFile] = [:],
    ) {
        self.init(
            updatedAtMs: updatedAtMs,
            schemaVersion: schemaVersion,
            lastUsedProviderId: lastUsedProviderId,
            lastUsedAtMs: lastUsedAtMs,
            providers: providers,
        )
    }

    /// Creates an empty file payload for missing-file or reset scenarios.
    public static func empty(updatedAtMs: Int64 = 0) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            schemaVersion: 1,
            providers: [:],
        )
    }

    /// Returns a copy with all provider credentials redacted for safe logging.
    public var redacted: AIConnectionsFile {
        AIConnectionsFile(
            schemaVersion: schemaVersion,
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: lastUsedProviderId,
            lastUsedAtMs: lastUsedAtMs,
            providers: providers.mapValues { $0.redacted },
        )
    }
}

// MARK: - Codable

extension AIConnectionsFile: Codable {}

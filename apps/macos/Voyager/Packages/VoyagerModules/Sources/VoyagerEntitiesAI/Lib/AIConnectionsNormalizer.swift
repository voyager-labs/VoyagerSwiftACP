import Foundation

public enum AIConnectionsNormalizer {
    public static func normalize(_ file: AIConnectionsFile) -> AIConnectionsFile {
        guard file.schemaVersion == 1 else {
            return AIConnectionsFile.empty(updatedAtMs: file.updatedAtMs)
        }

        var normalizedProviders: [String: ProviderRecordFile] = [:]

        for (key, record) in file.providers {
            guard key == record.providerId.rawValue else { continue }

            guard ProviderDescriptor.supportedProviders.contains(record.providerId) else { continue }

            let normalizedRecord = normalizeRecord(record)
            normalizedProviders[key] = normalizedRecord
        }

        return AIConnectionsFile(
            schemaVersion: 1,
            updatedAtMs: file.updatedAtMs,
            lastUsedProviderId: file.lastUsedProviderId,
            lastUsedAtMs: file.lastUsedAtMs,
            providers: normalizedProviders,
        )
    }

    public static func renderableProviders(
        from file: AIConnectionsFile,
    ) -> [String: ProviderRecordFile] {
        file.providers.filter { key, _ in
            guard let provider = AIProvider(rawValue: key) else { return false }
            return ProviderDescriptor.supportedProviders.contains(provider)
        }
    }

    private static func normalizeRecord(_ record: ProviderRecordFile) -> ProviderRecordFile {
        let expectedAuthMethod = ProviderDescriptor.descriptor(for: record.providerId)?.authMethod
        let credentialMatchesAuth = credentialKindMatches(
            record.credential,
            record.authMethod,
            expectedAuthMethod,
        )

        if record.credential == nil {
            return ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: nil,
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .notVerified,
                    lastVerifiedAtMs: record.snapshot.lastVerifiedAtMs,
                    lastErrorCode: .missingCredential,
                ),
            )
        }

        if !credentialMatchesAuth {
            return ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: record.credential,
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .failed,
                    lastVerifiedAtMs: record.snapshot.lastVerifiedAtMs,
                    lastErrorCode: .credentialKindMismatch,
                ),
            )
        }

        return record
    }

    private static func credentialKindMatches(
        _ credential: StoredCredentialPayload?,
        _: ProviderAuthMethod,
        _ expectedAuthMethod: ProviderAuthMethod?,
    ) -> Bool {
        guard let credential, let expectedAuthMethod else { return true }

        let catalogMethod = expectedAuthMethod
        let credentialIsOAuth = switch credential {
        case .oauth: true
        case .apiKey: false
        }

        return credentialIsOAuth == (catalogMethod == .oauth)
    }
}

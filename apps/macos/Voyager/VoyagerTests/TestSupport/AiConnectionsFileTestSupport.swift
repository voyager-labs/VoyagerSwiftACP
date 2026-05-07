import Foundation
import VoyagerEntitiesAi

extension OAuthCredentialFile {
    static func testFixture(accessToken: String = "test-access-token") -> OAuthCredentialFile {
        OAuthCredentialFile(accessToken: accessToken)
    }
}

extension APIKeyCredentialFile {
    static func testFixture(secret: String = "sk-test-valid") -> APIKeyCredentialFile {
        APIKeyCredentialFile(secret: secret)
    }
}

extension ProviderRecordFile {
    static func testFixture(
        provider: AiProvider,
        authMethod: ProviderAuthMethod,
        state: ProviderConnectionState = .connected,
        credential: StoredCredentialPayload? = nil,
    ) -> ProviderRecordFile {
        let resolvedCredential = credential ?? defaultCredential(for: authMethod)

        return ProviderRecordFile(
            providerId: provider,
            authMethod: authMethod,
            credential: resolvedCredential,
            snapshot: ProviderSnapshotFile(lastKnownStatus: state),
        )
    }

    private static func defaultCredential(for authMethod: ProviderAuthMethod) -> StoredCredentialPayload {
        switch authMethod {
        case .oauth, .codexCLI:
            .oauth(OAuthCredentialFile.testFixture())
        case .apiKey:
            .apiKey(APIKeyCredentialFile.testFixture())
        }
    }
}

extension AIConnectionsFile {
    static func testFixture(
        updatedAtMs: Int64 = 1,
        lastUsedProviderId: AiProvider? = nil,
        providers: [ProviderRecordFile] = [],
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: lastUsedProviderId,
            providers: Dictionary(uniqueKeysWithValues: providers.map { ($0.providerId.rawValue, $0) }),
        )
    }
}

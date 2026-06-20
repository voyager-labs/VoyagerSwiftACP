import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiProviderConnection

// MARK: - Credential Fixtures

extension OAuthCredentialFile {
    static func testFixture(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        idToken: String? = nil,
        tokenType: String? = "Bearer",
        scopes: [String] = ["openid", "profile"],
        expiresAtMs: Int64? = nil,
        chatGPTAccountId: String? = nil,
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            tokenType: tokenType,
            scopes: scopes,
            expiresAtMs: expiresAtMs,
            chatGPTAccountId: chatGPTAccountId,
        )
    }
}

extension APIKeyCredentialFile {
    static func testFixture(secret: String = "sk-test-valid") -> APIKeyCredentialFile {
        APIKeyCredentialFile(secret: secret)
    }
}

extension AiProviderConnectionResult {
    static func connectSuccess(
        provider: AiProvider,
        state: ProviderConnectionState = .connected,
        file: AIConnectionsFile = .empty(),
    ) -> AiProviderConnectionResult {
        AiProviderConnectionResult(
            provider: provider,
            state: state,
            reason: .none,
            updatedFile: file,
        )
    }
}

extension AIConnectionsFile {
    static func singleProvider(
        _ provider: AiProvider,
        state: ProviderConnectionState,
        credential: StoredCredentialPayload? = nil,
        errorCode: ProviderStatusReason = .none,
    ) -> AIConnectionsFile {
        let resolvedCredential = credential ?? defaultCredential(for: provider)
        let authMethod: ProviderAuthMethod = provider == .chatgptCodex ? .oauth : .apiKey

        return AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                provider.rawValue: ProviderRecordFile(
                    providerId: provider,
                    authMethod: authMethod,
                    credential: resolvedCredential,
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: state,
                        lastErrorCode: errorCode,
                    ),
                ),
            ],
        )
    }

    private static func defaultCredential(for provider: AiProvider) -> StoredCredentialPayload? {
        switch provider {
        case .chatgptCodex:
            .oauth(OAuthCredentialFile.testFixture())
        case .openai, .anthropic:
            .apiKey(APIKeyCredentialFile.testFixture())
        }
    }
}

import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

// MARK: - Credential Fixtures

extension OAuthCredentialFile {
    /// Deterministic test fixture. Does NOT perform real OAuth work.
    static func testFixture(
        accessToken: String = "test-access-token",
        refreshToken: String? = "test-refresh-token",
        idToken: String? = nil,
        tokenType: String? = "Bearer",
        scopes: [String] = ["openid", "profile"],
        expiresAtMs: Int64? = nil,
        chatGPTAccountId: String? = nil
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            tokenType: tokenType,
            scopes: scopes,
            expiresAtMs: expiresAtMs,
            chatGPTAccountId: chatGPTAccountId
        )
    }
}

extension APIKeyCredentialFile {
    /// Deterministic test fixture.
    static func testFixture(secret: String = "sk-test-valid") -> APIKeyCredentialFile {
        APIKeyCredentialFile(secret: secret)
    }
}

// MARK: - Connection Result Builders

extension AiProviderConnectionResult {
    /// Successful connect result echoing back the provider and target state.
    static func connectSuccess(
        provider: AiProvider,
        state: ProviderConnectionState = .connected,
        file: AIConnectionsFile = .empty()
    ) -> AiProviderConnectionResult {
        AiProviderConnectionResult(
            provider: provider,
            state: state,
            reason: .none,
            updatedFile: file
        )
    }

    /// Successful disconnect result — provider returns to `.notVerified`.
    static func disconnectSuccess(
        provider: AiProvider,
        file: AIConnectionsFile = .empty()
    ) -> AiProviderConnectionResult {
        AiProviderConnectionResult(
            provider: provider,
            state: .notVerified,
            reason: .none,
            updatedFile: file
        )
    }

    /// Failed connection result with a specific reason.
    static func failed(
        provider: AiProvider,
        reason: ProviderStatusReason = .unknown,
        file: AIConnectionsFile = .empty()
    ) -> AiProviderConnectionResult {
        AiProviderConnectionResult(
            provider: provider,
            state: .connectionFailed,
            reason: reason,
            updatedFile: file
        )
    }
}

// MARK: - AIConnectionsFile Builders

extension AIConnectionsFile {
    /// Creates a file with a single provider in the given state.
    static func singleProvider(
        _ provider: AiProvider,
        state: ProviderConnectionState,
        credential: StoredCredentialPayload? = nil,
        errorCode: ProviderStatusReason = .none
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
                        lastErrorCode: errorCode
                    )
                ),
            ]
        )
    }

    private static func defaultCredential(for provider: AiProvider) -> StoredCredentialPayload? {
        switch provider {
        case .chatgptCodex:
            return .oauth(OAuthCredentialFile.testFixture())
        case .openai, .anthropic:
            return .apiKey(APIKeyCredentialFile.testFixture())
        }
    }
}

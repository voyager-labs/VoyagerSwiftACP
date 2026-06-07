@testable import VoyagerEntitiesAi
import XCTest

final class AIProviderQuerySelectionTests: XCTestCase {
    func testSelectPrefersValidLastUsedConnectedProvider() throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            lastUsedProviderId: .anthropic,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let result = AIProviderQuerySelection.select(from: file)
        let expected = try AIProviderQuerySelectionContext(
            provider: .anthropic,
            record: XCTUnwrap(file.providers[AiProvider.anthropic.rawValue]),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
        )

        XCTAssertEqual(result, .success(expected))
    }

    func testSelectFallsBackToFirstConnectedProviderWhenLastUsedIsStale() throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnected),
                ),
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "at", refreshToken: "rt")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let result = AIProviderQuerySelection.select(from: file)
        let expected = try AIProviderQuerySelectionContext(
            provider: .chatgptCodex,
            record: XCTUnwrap(file.providers[AiProvider.chatgptCodex.rawValue]),
            credential: .oauth(OAuthCredentialFile(accessToken: "at", refreshToken: "rt")),
        )

        XCTAssertEqual(result, .success(expected))
    }

    func testSelectReturnsNotConfiguredWhenNoConnectedProvidersExist() {
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnected),
                ),
            ],
        )

        let result = AIProviderQuerySelection.select(from: file)

        XCTAssertEqual(result, .failure(.notConfigured))
    }

    func testSelectReturnsInvalidCredentialWhenConnectedCredentialKindMismatches() {
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .oauth(OAuthCredentialFile(accessToken: "at", refreshToken: "rt")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let result = AIProviderQuerySelection.select(from: file)

        XCTAssertEqual(
            result,
            .failure(.invalidCredential(provider: .openai, expected: .apiKey)),
        )
    }

    func testSelectReturnsProviderUnavailableForUnavailableConnectedRecord() {
        let file = AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .unavailable,
                        lastErrorCode: .providerUnsupportedInBuild,
                    ),
                ),
            ],
        )

        let result = AIProviderQuerySelection.select(from: file)

        XCTAssertEqual(
            result,
            .failure(.providerUnavailable(provider: .anthropic, reason: .providerUnsupportedInBuild)),
        )
    }
}

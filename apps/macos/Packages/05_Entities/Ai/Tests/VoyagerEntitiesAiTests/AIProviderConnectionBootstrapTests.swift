import VoyagerEntitiesAi
import XCTest

final class AIProviderConnectionBootstrapTests: XCTestCase {
    func testInitialResults_preserveCatalogOrderAndRestoreStates() {
        let file = AIConnectionsFile(
            updatedAtMs: 1_760_000_000_000,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture()),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .disconnecting),
                ),
            ],
        )

        let results = AIProviderConnectionBootstrap.initialResults(from: file)

        XCTAssertEqual(results.map(\.provider), ProviderDescriptor.v1Catalog.map(\.provider))
        XCTAssertEqual(
            results[0],
            AIProviderBootstrapResult(provider: .chatgptCodex, connectionState: .checkingStatus, statusReason: .none),
        )
        XCTAssertEqual(
            results[1],
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .notVerified,
                statusReason: .missingCredential,
            ),
        )
        XCTAssertEqual(
            results[2],
            AIProviderBootstrapResult(provider: .anthropic, connectionState: .disconnected, statusReason: .none),
        )
    }

    func testInitialResult_connectInProgressWithCredential_resetsToNotVerified() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(OAuthCredentialFile.testFixture()),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connectInProgress),
        )

        let result = AIProviderConnectionBootstrap.initialResult(for: .chatgptCodex, record: record)

        XCTAssertEqual(result.connectionState, .notVerified)
        XCTAssertEqual(result.statusReason, .none)
    }

    func testShouldVerify_excludesTransientDisconnectStatesOnly() {
        XCTAssertTrue(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .notVerified))
        XCTAssertTrue(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .checkingStatus))
        XCTAssertTrue(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .connected))
        XCTAssertTrue(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .connectionFailed))
        XCTAssertTrue(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .unavailable))
        XCTAssertFalse(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .connectInProgress))
        XCTAssertFalse(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .disconnecting))
        XCTAssertFalse(AIProviderConnectionBootstrap.shouldVerify(snapshotState: .disconnected))
    }

    func testVerifiedResult_mapsUnavailableAndFailureCases() {
        XCTAssertEqual(
            AIProviderConnectionBootstrap.verifiedResult(for: .openai, verification: .valid),
            AIProviderBootstrapResult(provider: .openai, connectionState: .connected, statusReason: .none),
        )
        XCTAssertEqual(
            AIProviderConnectionBootstrap.verifiedResult(
                for: .openai,
                verification: .invalid(.verificationFailed),
            ),
            AIProviderBootstrapResult(
                provider: .openai,
                connectionState: .connectionFailed,
                statusReason: .verificationFailed,
            ),
        )
        XCTAssertEqual(
            AIProviderConnectionBootstrap.verifiedResult(
                for: .anthropic,
                verification: .invalid(.providerUnsupportedInBuild),
            ),
            AIProviderBootstrapResult(
                provider: .anthropic,
                connectionState: .unavailable,
                statusReason: .providerUnsupportedInBuild,
            ),
        )
        XCTAssertEqual(
            AIProviderConnectionBootstrap.verifiedResult(for: .chatgptCodex, verification: .unsupportedProvider),
            AIProviderBootstrapResult(
                provider: .chatgptCodex,
                connectionState: .unavailable,
                statusReason: .providerUnsupportedInBuild,
            ),
        )
        XCTAssertEqual(
            AIProviderConnectionBootstrap.verifiedResult(for: .chatgptCodex, verification: .networkError),
            AIProviderBootstrapResult(
                provider: .chatgptCodex,
                connectionState: .connectionFailed,
                statusReason: .networkUnavailable,
            ),
        )
    }

    func testUpdatedConnectionsFile_appliesOnlyMatchingCredentials() {
        let sourceFile = matchingCredentialSourceFile()
        let latestFile = matchingCredentialLatestFile()

        let updatedFile = AIProviderConnectionBootstrap.updatedConnectionsFile(
            verificationSourceFile: sourceFile,
            latestFile: latestFile,
            applying: [
                AIProviderBootstrapResult(provider: .openai, connectionState: .connected, statusReason: .none),
                AIProviderBootstrapResult(
                    provider: .anthropic,
                    connectionState: .connectionFailed,
                    statusReason: .expired,
                ),
            ],
        )

        XCTAssertEqual(updatedFile?.providers[AiProvider.openai.rawValue]?.snapshot.lastKnownStatus, .connected)
        XCTAssertEqual(updatedFile?.providers[AiProvider.openai.rawValue]?.snapshot.lastVerifiedAtMs, 200)
        XCTAssertEqual(
            updatedFile?.providers[AiProvider.openai.rawValue]?.snapshot.lastErrorCode,
            ProviderStatusReason.none,
        )
        XCTAssertEqual(updatedFile?.providers[AiProvider.anthropic.rawValue]?.snapshot.lastKnownStatus, .checkingStatus)
        XCTAssertNil(updatedFile?.providers[AiProvider.anthropic.rawValue]?.snapshot.lastVerifiedAtMs)
        XCTAssertEqual(
            updatedFile?.providers[AiProvider.anthropic.rawValue]?.snapshot.lastErrorCode,
            ProviderStatusReason.none,
        )
    }

    func testUpdatedConnectionsFile_returnsNilWhenNothingChanges() {
        let latestFile = AIConnectionsFile(
            updatedAtMs: 200,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "same")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastVerifiedAtMs: nil,
                        lastErrorCode: .expired,
                    ),
                ),
            ],
        )

        let updatedFile = AIProviderConnectionBootstrap.updatedConnectionsFile(
            verificationSourceFile: latestFile,
            latestFile: latestFile,
            applying: [
                AIProviderBootstrapResult(
                    provider: .openai,
                    connectionState: .connectionFailed,
                    statusReason: .expired,
                ),
            ],
        )

        XCTAssertNil(updatedFile)
    }
}

private extension AIProviderConnectionBootstrapTests {
    func matchingCredentialSourceFile() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 100,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "source-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .checkingStatus),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "source-anthropic")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .checkingStatus),
                ),
            ],
        )
    }

    func matchingCredentialLatestFile() -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 200,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "source-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .checkingStatus),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile.testFixture(secret: "newer-anthropic")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .checkingStatus),
                ),
            ],
        )
    }
}

private extension OAuthCredentialFile {
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

private extension APIKeyCredentialFile {
    static func testFixture(secret: String = "sk-test-valid") -> APIKeyCredentialFile {
        APIKeyCredentialFile(secret: secret)
    }
}

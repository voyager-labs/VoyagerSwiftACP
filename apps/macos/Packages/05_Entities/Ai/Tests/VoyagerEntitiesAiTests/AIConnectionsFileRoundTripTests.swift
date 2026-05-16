@testable import VoyagerEntitiesAi
import XCTest

final class AIConnectionsFileRoundTripTests: XCTestCase {
    private var encoder: JSONEncoder { .init() }
    private var decoder: JSONDecoder { .init() }

    func testEmptyFileRoundTrip() throws {
        let original = AIConnectionsFile.empty()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.providers.isEmpty)
    }

    func testFileWithOAuthProviderRoundTrip() throws {
        let oauth = OAuthCredentialFile(
            accessToken: "at-123",
            refreshToken: "rt-456",
            idToken: "id-789",
            tokenType: "Bearer",
            scopes: ["read", "write"],
            expiresAtMs: 1_700_000_000_000,
            chatGPTAccountId: "account-123",
        )
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: .connected,
                lastVerifiedAtMs: 1_700_000_000_000,
                lastErrorCode: .none,
            ),
        )
        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 1_700_000_000_000,
            providers: ["chatgptCodex": record],
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFileWithAPIKeyProviderRoundTrip() throws {
        let apiKey = APIKeyCredentialFile(secret: "sk-test-key")
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .apiKey(apiKey),
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: .connected,
                lastVerifiedAtMs: 1_700_000_000_000,
            ),
        )
        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            providers: ["openai": record],
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testMultipleProvidersRoundTrip() throws {
        let oauthCred = OAuthCredentialFile(accessToken: "at", refreshToken: "rt")
        let apiCred = APIKeyCredentialFile(secret: "sk-key")

        let providers: [String: ProviderRecordFile] = [
            "chatgptCodex": ProviderRecordFile(
                providerId: .chatgptCodex,
                authMethod: .oauth,
                credential: .oauth(oauthCred),
                snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
            ),
            "openai": ProviderRecordFile(
                providerId: .openai,
                authMethod: .apiKey,
                credential: .apiKey(apiCred),
                snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
            ),
            "anthropic": ProviderRecordFile(
                providerId: .anthropic,
                authMethod: .apiKey,
                credential: nil,
                snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
            ),
        ]

        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 1_700_000_000_000,
            providers: providers,
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.providers.count, 3)
    }

    func testMixedSnapshotRoundTripPreservesLastUsedAndSnapshotMetadata() throws {
        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_123_456,
            lastUsedProviderId: .anthropic,
            lastUsedAtMs: 1_700_000_223_456,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connected,
                        lastVerifiedAtMs: 1_700_000_111_000,
                        lastErrorCode: .none,
                    ),
                ),
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .unavailable,
                        lastVerifiedAtMs: nil,
                        lastErrorCode: .providerUnsupportedInBuild,
                    ),
                ),
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "at", refreshToken: "rt")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connectionFailed,
                        lastVerifiedAtMs: 1_700_000_222_000,
                        lastErrorCode: .expired,
                    ),
                ),
            ],
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.lastUsedProviderId, .anthropic)
        XCTAssertEqual(decoded.lastUsedAtMs, 1_700_000_223_456)
        XCTAssertEqual(decoded.providers["anthropic"]?.snapshot.lastKnownStatus, .unavailable)
        XCTAssertEqual(decoded.providers["anthropic"]?.snapshot.lastErrorCode, .providerUnsupportedInBuild)
        XCTAssertEqual(decoded.providers["chatgptCodex"]?.snapshot.lastErrorCode, .expired)
    }

    func testStoredCredentialPayloadDecodingOauth() throws {
        let json = Data(
            """
            {"kind":"oauth","accessToken":"at","refreshToken":"rt","scopes":[],"expiresAtMs":null}
            """.utf8,
        )

        let decoded = try decoder.decode(StoredCredentialPayload.self, from: json)
        if case let .oauth(oauth) = decoded {
            XCTAssertEqual(oauth.accessToken, "at")
            XCTAssertEqual(oauth.refreshToken, "rt")
            XCTAssertNil(oauth.idToken)
            XCTAssertNil(oauth.chatGPTAccountId)
        } else {
            XCTFail("Expected oauth credential")
        }
    }

    func testStoredCredentialPayloadDecodingApiKey() throws {
        let json = Data(
            """
            {"kind":"apiKey","secret":"sk-abc"}
            """.utf8,
        )

        let decoded = try decoder.decode(StoredCredentialPayload.self, from: json)
        if case let .apiKey(apiKey) = decoded {
            XCTAssertEqual(apiKey.secret, "sk-abc")
        } else {
            XCTFail("Expected apiKey credential")
        }
    }

    func testStoredCredentialPayloadUnknownKindThrows() {
        let json = Data(
            """
            {"kind":"unknown","secret":"x"}
            """.utf8,
        )

        XCTAssertThrowsError(try decoder.decode(StoredCredentialPayload.self, from: json))
    }
}

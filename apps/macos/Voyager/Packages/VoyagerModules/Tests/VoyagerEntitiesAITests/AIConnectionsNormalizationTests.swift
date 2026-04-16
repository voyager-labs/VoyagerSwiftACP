import Foundation
@testable import VoyagerEntitiesAI
import XCTest

final class AIConnectionsNormalizationTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - Provider-key matching

    func testNormalize_rejectsProviderKeyMismatch() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let chatgptRecord = normalized.providers["chatgptCodex"]

        // Key "chatgptCodex" doesn't match providerId .openai → should be omitted or fixed
        XCTAssertNil(chatgptRecord)
    }

    func testNormalize_keepsMatchingProviderKey() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertNotNil(normalized.providers["openai"])
        XCTAssertEqual(normalized.providers["openai"]?.providerId, .openai)
    }

    // MARK: - Auth-method validity

    func testNormalize_rejectsOAuthProviderWithAPIKeyCredential() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-wrong")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let chatgpt = normalized.providers["chatgptCodex"]
        XCTAssertNotNil(chatgpt)
        XCTAssertEqual(chatgpt?.snapshot.lastKnownStatus, .failed)
        XCTAssertEqual(chatgpt?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    func testNormalize_rejectsAPIKeyProviderWithOAuthCredential() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .oauth(
                OAuthCredentialFile(accessToken: "at-wrong"),
            ),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let openai = normalized.providers["openai"]
        XCTAssertNotNil(openai)
        XCTAssertEqual(openai?.snapshot.lastKnownStatus, .failed)
        XCTAssertEqual(openai?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    func testNormalize_acceptsMatchingAuthMethod_oauth() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(
                OAuthCredentialFile(accessToken: "at-ok"),
            ),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers["chatgptCodex"]?.snapshot.lastKnownStatus, .connected)
    }

    func testNormalize_acceptsMatchingAuthMethod_apiKey() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ok")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers["openai"]?.snapshot.lastKnownStatus, .connected)
    }

    // MARK: - Nil credential forces notVerified

    func testNormalize_nilCredential_forcesNotVerified() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: nil,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let openai = normalized.providers["openai"]
        XCTAssertNotNil(openai)
        XCTAssertEqual(openai?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertEqual(openai?.snapshot.lastErrorCode, .missingCredential)
    }

    func testNormalize_nilCredential_overridesFailedToNotVerified() {
        let record = ProviderRecordFile(
            providerId: .anthropic,
            authMethod: .apiKey,
            credential: nil,
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: .failed,
                lastErrorCode: .expired,
            ),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["anthropic": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let anthropic = normalized.providers["anthropic"]
        XCTAssertEqual(anthropic?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertEqual(anthropic?.snapshot.lastErrorCode, .missingCredential)
    }

    // MARK: - Unsupported provider omission

    func testNormalize_omitsUnsupportedProviderFromRenderable() {
        let supportedRecord = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
        )
        // Use a JSON with an unsupported key to simulate historical data
        var providers = fileFromJSON(
            """
            {
              "schemaVersion": 1,
              "updatedAtMs": 1000,
              "providers": {
                "openai": {
                  "providerId": "openai",
                  "authMethod": "apiKey",
                  "snapshot": { "lastKnownStatus": "notVerified", "lastErrorCode": "none" }
                },
                "unknownProvider": {
                  "providerId": "openai",
                  "authMethod": "apiKey",
                  "snapshot": { "lastKnownStatus": "notVerified", "lastErrorCode": "none" }
                }
              }
            }
            """,
        )

        let normalized = AIConnectionsNormalizer.normalize(providers)
        XCTAssertNotNil(normalized.providers["openai"])
        XCTAssertNil(normalized.providers["unknownProvider"])
    }

    // MARK: - Schema version policy

    func testNormalize_unsupportedVersion_producesEmptyFile() {
        let file = AIConnectionsFile(
            schemaVersion: 99,
            updatedAtMs: 1000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let result = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertTrue(result.providers.isEmpty)
    }

    func testNormalize_version1_passesThrough() {
        let file = AIConnectionsFile(
            schemaVersion: 1,
            updatedAtMs: 1000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let result = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.providers.count, 1)
    }

    // MARK: - Auth method consistency with v1 catalog

    func testNormalize_rejectsOAuthRecordForAPIKeyOnlyProvider() {
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .oauth,
            credential: .oauth(OAuthCredentialFile(accessToken: "bad")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let openai = normalized.providers["openai"]
        XCTAssertNotNil(openai)
        XCTAssertEqual(openai?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    func testNormalize_rejectsAPIKeyRecordForOAuthOnlyProvider() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .apiKey,
            credential: .apiKey(APIKeyCredentialFile(secret: "bad")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let chatgpt = normalized.providers["chatgptCodex"]
        XCTAssertNotNil(chatgpt)
        XCTAssertEqual(chatgpt?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    // MARK: - Empty file normalization

    func testNormalize_emptyFile_remainsEmpty() {
        let file = AIConnectionsFile.empty(updatedAtMs: 0)
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers, [:])
        XCTAssertEqual(normalized.schemaVersion, 1)
    }

    // MARK: - Multiple providers

    func testNormalize_multipleProviders_independentlyNormalized() {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "at-ok")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers["chatgptCodex"]?.snapshot.lastKnownStatus, .connected)
        XCTAssertEqual(normalized.providers["openai"]?.snapshot.lastKnownStatus, .notVerified)
    }

    // MARK: - Renderable providers

    func testRenderableProviders_filtersToSupportedOnly() {
        let file = fileFromJSON(
            """
            {
              "schemaVersion": 1,
              "updatedAtMs": 1000,
              "providers": {
                "chatgptCodex": {
                  "providerId": "chatgptCodex",
                  "authMethod": "oauth",
                  "credential": { "kind": "oauth", "accessToken": "at" },
                  "snapshot": { "lastKnownStatus": "connected", "lastErrorCode": "none" }
                },
                "futureProvider": {
                  "providerId": "futureProvider",
                  "authMethod": "apiKey",
                  "snapshot": { "lastKnownStatus": "notVerified", "lastErrorCode": "none" }
                }
              }
            }
            """,
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let renderable = AIConnectionsNormalizer.renderableProviders(from: normalized)

        XCTAssertEqual(renderable.count, 1)
        XCTAssertEqual(renderable.first?.key, "chatgptCodex")
    }

    func testRenderableProviders_includesAllSupported() {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
                ),
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
                ),
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
                ),
            ],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let renderable = AIConnectionsNormalizer.renderableProviders(from: normalized)
        XCTAssertEqual(Set(renderable.keys), ProviderDescriptor.supportedProviders.map(\.rawValue))
    }

    // MARK: - Helpers

    private func fileFromJSON(_ jsonString: String) -> AIConnectionsFile {
        let data = jsonString.data(using: .utf8)!
        return try! decoder.decode(AIConnectionsFile.self, from: data)
    }
}

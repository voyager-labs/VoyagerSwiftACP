import Foundation
@testable import VoyagerEntitiesAi
import XCTest

/// Recovered from old CodexImportRegressionTests (9d3be186).
/// Adapted: CodexAuthFileParser removed — test data constructed directly.
/// JSON fixtures include required "scopes" field for current Codable conformance.
/// Normalizer now preserves .codexCLI (treats it as valid OAuth variant).
final class CodexImportNormalizationTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    private let decoder = JSONDecoder()

    // MARK: - Normalizer: .codexCLI with .oauth credential passes through

    func testNormalization_codexCLI_withOAuth_credential_passesThrough() {
        let oauthCred = OAuthCredentialFile(
            accessToken: "at_fixture_full",
            refreshToken: "rt_fixture_full",
            tokenType: "Bearer",
            scopes: ["profile", "email", "openid"],
            expiresAtMs: 1_760_003_600_000,
        )

        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .codexCLI,
            credential: .oauth(oauthCred),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let codex = normalized.providers["chatgptCodex"]
        XCTAssertNotNil(codex)
        XCTAssertEqual(codex?.authMethod, .codexCLI)
        XCTAssertEqual(codex?.snapshot.lastKnownStatus, .connected)
        XCTAssertEqual(codex?.snapshot.lastErrorCode, .none)
    }

    // MARK: - Normalizer: credential kind mismatch

    func testNormalization_chatgptCodex_apiKey_withOAuth_failsCredentialKindMismatch() {
        let oauthCred = OAuthCredentialFile(accessToken: "at_minimal")

        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .apiKey,
            credential: .oauth(oauthCred),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let codex = normalized.providers["chatgptCodex"]
        XCTAssertNotNil(codex)
        XCTAssertEqual(codex?.snapshot.lastKnownStatus, .connectionFailed)
        XCTAssertEqual(codex?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    // MARK: - Full pipeline: legacy .codexCLI JSON → normalize → preserved

    func testFullPipeline_legacyCodexCLIJsonFile_preservedAfterNormalization() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "updatedAtMs": 1000,
            "providers": {
                "chatgptCodex": {
                    "providerId": "chatgptCodex",
                    "authMethod": "codexCLI",
                    "credential": {
                        "kind": "oauth",
                        "accessToken": "at_pipeline_legacy",
                        "scopes": []
                    },
                    "snapshot": {
                        "lastKnownStatus": "connected",
                        "lastErrorCode": "none"
                    }
                }
            }
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)

        let codexBefore = try XCTUnwrap(decoded.providers["chatgptCodex"])
        XCTAssertEqual(codexBefore.authMethod, .codexCLI)

        let normalized = AIConnectionsNormalizer.normalize(decoded)
        let codexAfter = try XCTUnwrap(normalized.providers["chatgptCodex"])

        XCTAssertEqual(codexAfter.authMethod, .codexCLI)
        XCTAssertEqual(codexAfter.snapshot.lastKnownStatus, .connected)
        XCTAssertEqual(codexAfter.snapshot.lastErrorCode, .none)

        if case let .oauth(oauthCred) = codexAfter.credential {
            XCTAssertEqual(oauthCred.accessToken, "at_pipeline_legacy")
        } else {
            XCTFail("Credential must remain .oauth after normalization")
        }
    }

    // MARK: - Canonical .oauth JSON passes through unchanged

    func testFullPipeline_canonicalOAuthJsonFile_passesThroughUnchanged() throws {
        let canonicalJSON = """
        {
            "schemaVersion": 1,
            "updatedAtMs": 2000,
            "providers": {
                "chatgptCodex": {
                    "providerId": "chatgptCodex",
                    "authMethod": "oauth",
                    "credential": {
                        "kind": "oauth",
                        "accessToken": "at_pipeline_canonical",
                        "scopes": []
                    },
                    "snapshot": {
                        "lastKnownStatus": "connected",
                        "lastErrorCode": "none"
                    }
                }
            }
        }
        """
        let data = try XCTUnwrap(canonicalJSON.data(using: .utf8))
        let decoded = try decoder.decode(AIConnectionsFile.self, from: data)
        let normalized = AIConnectionsNormalizer.normalize(decoded)
        let codex = try XCTUnwrap(normalized.providers["chatgptCodex"])

        XCTAssertEqual(codex.authMethod, .oauth)
        XCTAssertNil(codex.provenance)
        XCTAssertEqual(codex.snapshot.lastKnownStatus, .connected)
    }

    // MARK: - Legacy .codexCLI decode

    func testProviderRecordFile_legacyCodexCLI_decodes() throws {
        let json = """
        {
            "providerId": "chatgptCodex",
            "authMethod": "codexCLI",
            "credential": {
                "kind": "oauth",
                "accessToken": "at_legacy",
                "scopes": []
            },
            "snapshot": {
                "lastKnownStatus": "connected",
                "lastErrorCode": "none"
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try decoder.decode(ProviderRecordFile.self, from: data)

        XCTAssertEqual(decoded.providerId, .chatgptCodex)
        XCTAssertEqual(decoded.authMethod, .codexCLI)
        XCTAssertNil(decoded.provenance)
    }
}

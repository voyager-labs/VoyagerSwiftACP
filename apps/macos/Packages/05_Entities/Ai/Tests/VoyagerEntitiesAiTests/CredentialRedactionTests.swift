@testable import VoyagerEntitiesAi
import XCTest

final class CredentialRedactionTests: XCTestCase {
    func testOAuthPayloadRedactionMasksAccessToken() {
        let oauth = OAuthCredentialFile(
            accessToken: "secret-access-token",
            refreshToken: "secret-refresh-token",
            idToken: "secret-id-token",
            tokenType: "Bearer",
            scopes: ["read"],
            expiresAtMs: 1_700_000_000_000,
            chatGPTAccountId: "account-123"
        )
        let payload = StoredCredentialPayload.oauth(oauth)
        let redacted = payload.redacted

        if case let .oauth(r) = redacted {
            XCTAssertEqual(r.accessToken, "****")
            XCTAssertEqual(r.refreshToken, "****")
            XCTAssertEqual(r.idToken, "****")
            XCTAssertEqual(r.tokenType, "Bearer")
            XCTAssertEqual(r.scopes, ["read"])
            XCTAssertEqual(r.chatGPTAccountId, "account-123")
        } else {
            XCTFail("Expected oauth")
        }
    }

    func testOAuthPayloadRedactionWithNilRefreshToken() {
        let oauth = OAuthCredentialFile(accessToken: "secret", refreshToken: nil)
        let payload = StoredCredentialPayload.oauth(oauth)
        let redacted = payload.redacted

        if case let .oauth(r) = redacted {
            XCTAssertEqual(r.accessToken, "****")
            XCTAssertNil(r.refreshToken)
        } else {
            XCTFail("Expected oauth")
        }
    }

    func testApiKeyPayloadRedaction() {
        let apiKey = APIKeyCredentialFile(secret: "sk-super-secret-key")
        let payload = StoredCredentialPayload.apiKey(apiKey)
        let redacted = payload.redacted

        if case let .apiKey(r) = redacted {
            XCTAssertEqual(r.secret, "****")
        } else {
            XCTFail("Expected apiKey")
        }
    }

    func testDebugDescriptionExcludesRealSecrets() {
        let oauth = OAuthCredentialFile(
            accessToken: "real-access-token-abc",
            refreshToken: "real-refresh-token-xyz"
        )
        let payload = StoredCredentialPayload.oauth(oauth)
        let debug = payload.debugDescription

        XCTAssertFalse(debug.contains("real-access-token-abc"))
        XCTAssertFalse(debug.contains("real-refresh-token-xyz"))
        XCTAssertTrue(debug.contains("****"))
    }

    func testProviderRecordRedactionPreservesMetadata() {
        let oauth = OAuthCredentialFile(accessToken: "secret-at")
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let redacted = record.redacted

        XCTAssertEqual(redacted.providerId, .chatgptCodex)
        XCTAssertEqual(redacted.authMethod, .oauth)
        if case let .oauth(r) = redacted.credential {
            XCTAssertEqual(r.accessToken, "****")
        } else {
            XCTFail("Expected oauth")
        }
    }

    func testFileRedactionPreservesStructure() {
        let oauth = OAuthCredentialFile(accessToken: "top-secret")
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .chatgptCodex,
            providers: ["chatgptCodex": record]
        )

        let redacted = file.redacted
        XCTAssertEqual(redacted.updatedAtMs, 1000)
        XCTAssertEqual(redacted.lastUsedProviderId, .chatgptCodex)
        if case let .oauth(r) = redacted.providers["chatgptCodex"]?.credential {
            XCTAssertEqual(r.accessToken, "****")
        } else {
            XCTFail("Expected oauth")
        }
    }
}

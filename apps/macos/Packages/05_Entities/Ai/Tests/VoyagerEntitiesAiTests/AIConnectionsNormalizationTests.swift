@testable import VoyagerEntitiesAi
import XCTest

final class AIConnectionNormalizationTests: XCTestCase {
    func testNormalizeEmptyFile() {
        let file = AIConnectionsFile.empty(updatedAtMs: 1000)
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.schemaVersion, 1)
        XCTAssertTrue(normalized.providers.isEmpty)
    }

    func testNormalizeRejectsUnknownSchemaVersion() {
        let file = AIConnectionsFile(
            schemaVersion: 99,
            updatedAtMs: 1000,
            providers: [:]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertTrue(normalized.providers.isEmpty)
        XCTAssertEqual(normalized.schemaVersion, 1)
    }

    func testNormalizeRemovesKeyMismatchRecord() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["wrongKey": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertTrue(normalized.providers.isEmpty)
    }

    func testNormalizeRemovesUnsupportedProvider() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record, "unknownProvider": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers.count, 1)
        XCTAssertNotNil(normalized.providers["chatgptCodex"])
    }

    func testNormalizeNilCredentialSetsNotVerified() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: nil,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        let normalizedRecord = normalized.providers["chatgptCodex"]
        XCTAssertEqual(normalizedRecord?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertEqual(normalizedRecord?.snapshot.lastErrorCode, .missingCredential)
    }

    func testNormalizeCredentialKindMismatchSetsFailed() {
        let apiCred = APIKeyCredentialFile(secret: "sk-key")
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .apiKey(apiCred),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        let normalizedRecord = normalized.providers["chatgptCodex"]
        XCTAssertEqual(normalizedRecord?.snapshot.lastKnownStatus, .connectionFailed)
        XCTAssertEqual(normalizedRecord?.snapshot.lastErrorCode, .credentialKindMismatch)
    }

    func testNormalizeValidOAuthRecordPassesThrough() {
        let oauth = OAuthCredentialFile(accessToken: "at", refreshToken: "rt")
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers["chatgptCodex"], record)
    }

    func testNormalizeValidApiKeyRecordPassesThrough() {
        let apiCred = APIKeyCredentialFile(secret: "sk-key")
        let record = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .apiKey(apiCred),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["openai": record]
        )
        let normalized = AIConnectionsNormalizer.normalize(file)
        XCTAssertEqual(normalized.providers["openai"], record)
    }

    func testRenderableProvidersFiltersCorrectly() {
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: ["chatgptCodex": record, "nonExistentProvider": record]
        )
        let renderable = AIConnectionsNormalizer.renderableProviders(from: file)
        XCTAssertEqual(renderable.count, 1)
        XCTAssertNotNil(renderable["chatgptCodex"])
    }
}

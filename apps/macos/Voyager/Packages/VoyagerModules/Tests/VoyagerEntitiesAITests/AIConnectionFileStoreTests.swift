import Darwin
import Foundation
@testable import VoyagerEntitiesAI
import XCTest

final class AIConnectionFileStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(
            "AIConnectionFileStoreTests-\(UUID().uuidString)",
            isDirectory: true,
        )
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private var payloadURL: URL {
        AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: tempDir)
    }

    private var lockURL: URL {
        AIConnectionFSLocation.lockFileURL(homeDirectoryURL: tempDir)
    }

    private var directoryURL: URL {
        AIConnectionFSLocation.directoryURL(homeDirectoryURL: tempDir)
    }

    // MARK: - Missing file returns empty

    func testLoad_missingFile_returnsEmptyPayload() async throws {
        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())
    }

    // MARK: - Valid file loads successfully

    func testLoad_validFile_returnsDecodedPayload() async throws {
        let file = AIConnectionsFile(
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
        try writeJSON(file, to: payloadURL)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()
        XCTAssertEqual(result.providers.count, 1)
        XCTAssertEqual(result.providers["openai"]?.providerId, .openai)
    }

    // MARK: - Write creates directory and file

    func testWrite_createsDirectoryAndFile() async throws {
        XCTAssertFalse(fileManager.fileExists(atPath: directoryURL.path))

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let file = AIConnectionsFile(updatedAtMs: 5000)
        try await store.write(file)

        XCTAssertTrue(fileManager.fileExists(atPath: directoryURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: payloadURL.path))
    }

    // MARK: - Write then load round-trips

    func testWriteThenLoad_roundTrips() async throws {
        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let original = AIConnectionsFile(
            updatedAtMs: 9999,
            lastUsedProviderId: .anthropic,
            lastUsedAtMs: 8888,
            providers: [
                "anthropic": ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "ant-key")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(original)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.updatedAtMs, 9999)
        XCTAssertEqual(loaded.lastUsedProviderId, .anthropic)
        XCTAssertEqual(loaded.providers.count, 1)
    }

    // MARK: - Corrupted file quarantined

    func testLoad_corruptedFile_quarantinesAndReturnsEmpty() async throws {
        let corruptedData = "{ invalid json !!!".data(using: .utf8)!
        try ensureDirectoryExists()
        try corruptedData.write(to: payloadURL, options: .atomic)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()

        XCTAssertEqual(result, AIConnectionsFile.empty())
        XCTAssertFalse(fileManager.fileExists(atPath: payloadURL.path))

        let quarantineFiles = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("ai_connections.corrupted-") }
        XCTAssertEqual(quarantineFiles.count, 1)
    }

    // MARK: - Empty file quarantined

    func testLoad_emptyFile_quarantinesAndReturnsEmpty() async throws {
        try ensureDirectoryExists()
        try Data().write(to: payloadURL, options: .atomic)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())
        XCTAssertFalse(fileManager.fileExists(atPath: payloadURL.path))
    }

    // MARK: - Full file replacement on write

    func testWrite_replacesEntireFile() async throws {
        try ensureDirectoryExists()
        let file1 = AIConnectionsFile(
            updatedAtMs: 1000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .notVerified),
                ),
            ],
        )
        try writeJSON(file1, to: payloadURL)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let file2 = AIConnectionsFile(
            updatedAtMs: 2000,
            providers: [
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(file2)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.updatedAtMs, 2000)
        XCTAssertNil(loaded.providers["openai"])
        XCTAssertNotNil(loaded.providers["chatgptCodex"])
    }

    // MARK: - Per-record salvage: valid records survive alongside corrupted

    func testLoad_partialCorruption_salvagesValidRecords() async throws {
        let json = """
        {
          "schemaVersion": 1,
          "updatedAtMs": 1000,
          "providers": {
            "openai": {
              "providerId": "openai",
              "authMethod": "apiKey",
              "snapshot": { "lastKnownStatus": "notVerified", "lastErrorCode": "none" }
            },
            "chatgptCodex": {
              "providerId": "chatgptCodex",
              "authMethod": "oauth",
              "snapshot": { "lastKnownStatus": "connected", "lastErrorCode": "none" }
            }
          }
        }
        """
        try ensureDirectoryExists()
        try json.data(using: .utf8)!.write(to: payloadURL, options: .atomic)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()
        XCTAssertEqual(result.providers.count, 2)
        XCTAssertNotNil(result.providers["openai"])
        XCTAssertNotNil(result.providers["chatgptCodex"])
    }

    // MARK: - Load normalizes after read

    func testLoad_normalizesFile() async throws {
        let json = """
        {
          "schemaVersion": 1,
          "updatedAtMs": 1000,
          "providers": {
            "openai": {
              "providerId": "openai",
              "authMethod": "apiKey",
              "credential": null,
              "snapshot": { "lastKnownStatus": "connected", "lastErrorCode": "none" }
            }
          }
        }
        """
        try ensureDirectoryExists()
        try json.data(using: .utf8)!.write(to: payloadURL, options: .atomic)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        let result = try await store.load()
        let openai = result.providers["openai"]
        XCTAssertEqual(openai?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertEqual(openai?.snapshot.lastErrorCode, .missingCredential)
    }

    // MARK: - Delete removes credential and resets snapshot

    func testDeleteCredential_resetsProviderToNotVerified() async throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 999,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try writeJSON(file, to: payloadURL)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        try await store.deleteCredential(for: .openai)

        let loaded = try await store.load()
        let openai = loaded.providers["openai"]
        XCTAssertNotNil(openai)
        XCTAssertNil(openai?.credential)
        XCTAssertEqual(openai?.snapshot.lastKnownStatus, .notVerified)
        XCTAssertNotEqual(loaded.lastUsedProviderId, .openai)
    }

    // MARK: - Delete clears lastUsedProviderId if matching

    func testDeleteCredential_clearsLastUsedIfSameProvider() async throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 500,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try writeJSON(file, to: payloadURL)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        try await store.deleteCredential(for: .openai)

        let loaded = try await store.load()
        XCTAssertNil(loaded.lastUsedProviderId)
        XCTAssertNil(loaded.lastUsedAtMs)
    }

    // MARK: - Delete non-matching lastUsedProviderId preserves it

    func testDeleteCredential_preservesLastUsedIfDifferentProvider() async throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 500,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
                "chatgptCodex": ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "at")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try writeJSON(file, to: payloadURL)

        let store = AIConnectionFileStore(
            fileManager: fileManager,
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
        try await store.deleteCredential(for: .openai)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.lastUsedProviderId, .chatgptCodex)
        XCTAssertEqual(loaded.lastUsedAtMs, 500)
    }

    // MARK: - Helpers

    private func writeJSON(_ file: AIConnectionsFile, to url: URL) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

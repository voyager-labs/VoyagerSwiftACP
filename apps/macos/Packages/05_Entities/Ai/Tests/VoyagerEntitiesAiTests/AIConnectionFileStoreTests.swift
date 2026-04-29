@testable import VoyagerEntitiesAi
import XCTest

final class AIConnectionFileStoreTests: XCTestCase {
    private var tmpDir: URL!
    private var homeURL: URL!
    private var store: AIConnectionFileStore!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        homeURL = tmpDir

        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        let lockURL = AIConnectionFSLocation.lockFileURL(homeDirectoryURL: homeURL)
        store = AIConnectionFileStore(
            payloadURL: payloadURL,
            lockURL: lockURL
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: - Load

    func testLoadReturnsEmptyWhenFileMissing() async throws {
        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())
    }

    func testLoadReturnsNormalizedFile() async throws {
        let oauth = OAuthCredentialFile(accessToken: "at", refreshToken: "rt")
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
        try await store.write(file)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.providers["chatgptCodex"]?.providerId, .chatgptCodex)
    }

    func testLoadQuarantinesCorruptJSON() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not valid json".utf8).write(to: payloadURL)

        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())

        let dirContents = try FileManager.default.contentsOfDirectory(
            at: payloadURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let quarantined = dirContents.filter { $0.lastPathComponent.hasPrefix("auth.corrupted") }
        XCTAssertEqual(quarantined.count, 1, "Corrupt file should be quarantined")

        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testLoadQuarantinesEmptyFile() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: payloadURL)

        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    // MARK: - Write

    func testWriteCreatesFileWithCorrectPermissions() async throws {
        let file = AIConnectionsFile.empty(updatedAtMs: 1234)
        try await store.write(file)

        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: payloadURL.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o600, "File must have owner-only 0600 permissions")
    }

    func testWriteCreatesParentDirectory() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        let configDir = payloadURL.deletingLastPathComponent()

        XCTAssertFalse(FileManager.default.fileExists(atPath: configDir.path))

        let file = AIConnectionsFile.empty(updatedAtMs: 5678)
        try await store.write(file)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testWriteOverwritesExistingFile() async throws {
        let file1 = AIConnectionsFile.empty(updatedAtMs: 1000)
        try await store.write(file1)

        let file2 = AIConnectionsFile(
            updatedAtMs: 2000,
            lastUsedProviderId: .chatgptCodex,
            providers: [:]
        )
        try await store.write(file2)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.updatedAtMs, 2000)
        XCTAssertEqual(loaded.lastUsedProviderId, .chatgptCodex)
    }

    // MARK: - Round-trip

    func testLoadSaveRoundTrip() async throws {
        let oauth = OAuthCredentialFile(
            accessToken: "test-at",
            refreshToken: "test-rt",
            scopes: ["scope1"],
            expiresAtMs: 1_700_000_000_000
        )
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: .connected,
                lastVerifiedAtMs: 1_700_000_000_000
            )
        )
        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 1_700_000_000_000,
            providers: ["chatgptCodex": record]
        )

        try await store.write(original)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(loaded.updatedAtMs, original.updatedAtMs)
        XCTAssertEqual(loaded.lastUsedProviderId, original.lastUsedProviderId)
        XCTAssertEqual(loaded.providers.count, 1)

        guard let loadedRecord = loaded.providers["chatgptCodex"] else {
            XCTFail("Expected chatgptCodex provider")
            return
        }
        XCTAssertEqual(loadedRecord.providerId, .chatgptCodex)
        XCTAssertEqual(loadedRecord.authMethod, .oauth)
        XCTAssertEqual(loadedRecord.snapshot.lastKnownStatus, .connected)
    }

    // MARK: - Delete credential

    func testDeleteCredentialRemovesCredentialAndResetsState() async throws {
        let oauth = OAuthCredentialFile(accessToken: "at", refreshToken: "rt")
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected)
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 1000,
            providers: ["chatgptCodex": record]
        )
        try await store.write(file)

        try await store.deleteCredential(for: .chatgptCodex)

        let loaded = try await store.load()
        guard let updated = loaded.providers["chatgptCodex"] else {
            XCTFail("Provider record should still exist")
            return
        }
        XCTAssertNil(updated.credential)
        XCTAssertEqual(updated.snapshot.lastKnownStatus, .notVerified)
        XCTAssertNil(loaded.lastUsedProviderId)
        XCTAssertNil(loaded.lastUsedAtMs)
    }

    func testDeleteCredentialForAbsentProviderIsNoOp() async throws {
        let file = AIConnectionsFile.empty(updatedAtMs: 1000)
        try await store.write(file)

        try await store.deleteCredential(for: .anthropic)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.providers.count, 0)
    }

    // MARK: - Quarantine permissions

    func testQuarantinedFileHasOwnerOnlyPermissions() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("corrupt content".utf8).write(to: payloadURL)

        _ = try await store.load()

        let dirContents = try FileManager.default.contentsOfDirectory(
            at: payloadURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let quarantined = dirContents.filter { $0.lastPathComponent.hasPrefix("auth.corrupted") }
        guard let qFile = quarantined.first else {
            XCTFail("Expected quarantined file")
            return
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: qFile.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o600, "Quarantined file must have 0600 permissions")
    }
}

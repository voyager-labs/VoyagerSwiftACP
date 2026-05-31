@testable import VoyagerEntitiesAi
import XCTest

final class AIConnectionFileStoreTests: XCTestCase {
    private var fixture: TemporaryHomeFixture!
    private var store: AIConnectionFileStore!

    override func setUp() async throws {
        try await super.setUp()
        fixture = try TemporaryHomeFixture(createVoyagerDirectory: false)

        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        let lockURL = AIConnectionFSLocation.lockFileURL(homeDirectoryURL: fixture.homeURL)
        store = AIConnectionFileStore(
            payloadURL: payloadURL,
            lockURL: lockURL,
        )
    }

    override func tearDown() async throws {
        fixture = nil
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
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .chatgptCodex,
            providers: ["chatgptCodex": record],
        )
        try await store.write(file)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.providers["chatgptCodex"]?.providerId, .chatgptCodex)
    }

    func testLoadNormalizesMissingCredentialSnapshotWhilePreservingLastUsedMetadata() async throws {
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .openai,
            lastUsedAtMs: 2000,
            providers: [
                "openai": ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(file)

        let loaded = try await store.load()
        let record = try XCTUnwrap(loaded.providers["openai"])
        XCTAssertEqual(loaded.lastUsedProviderId, .openai)
        XCTAssertEqual(loaded.lastUsedAtMs, 2000)
        XCTAssertEqual(record.snapshot.lastKnownStatus, .notVerified)
        XCTAssertEqual(record.snapshot.lastErrorCode, .missingCredential)
    }

    func testMigrateFromHomeIfNeededWritesPayloadWithCorrectPermissions() async throws {
        let homePayloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        try FileManager.default.createDirectory(
            at: homePayloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        let file = AIConnectionsFile.empty(updatedAtMs: 1234)
        try await store.write(file)

        let repoRootURL = fixture.homeURL.appendingPathComponent("repo-root", isDirectory: true)
        try FileManager.default.createDirectory(at: repoRootURL, withIntermediateDirectories: true)
        let repoStore = AIConnectionFileStore.withRepoRoot(repoRootURL: repoRootURL)

        try await repoStore.migrateFromHomeIfNeeded(homeDirectoryURL: fixture.homeURL)

        let payloadURL = AIConnectionFSLocation.projectPayloadFileURL(repoRootURL: repoRootURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: payloadURL.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o600, "Migrated file must have owner-only 0600 permissions")

        let loaded = try await repoStore.load()
        XCTAssertEqual(loaded.updatedAtMs, file.updatedAtMs)
    }

    func testLoadQuarantinesCorruptJSON() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("{ not valid json".utf8).write(to: payloadURL)

        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())

        let dirContents = try FileManager.default.contentsOfDirectory(
            at: payloadURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
        )
        let quarantined = dirContents.filter { $0.lastPathComponent.hasPrefix("auth.corrupted") }
        XCTAssertEqual(quarantined.count, 1, "Corrupt file should be quarantined")

        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    func testLoadQuarantinesEmptyFile() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data().write(to: payloadURL)

        let result = try await store.load()
        XCTAssertEqual(result, AIConnectionsFile.empty())
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
    }

    // MARK: - Write

    func testWriteCreatesFileWithCorrectPermissions() async throws {
        let file = AIConnectionsFile.empty(updatedAtMs: 1234)
        let before = fixture.snapshotRealAuthFile()

        try await store.write(file)

        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: payloadURL.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o600, "File must have owner-only 0600 permissions")

        let after = fixture.snapshotRealAuthFile()
        XCTAssertEqual(after, before, "Writing isolated storage must not touch the real auth file")
    }

    func testWriteCreatesParentDirectoryWithOwnerOnlyPermissions() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        let configDir = payloadURL.deletingLastPathComponent()

        XCTAssertFalse(FileManager.default.fileExists(atPath: configDir.path))

        let file = AIConnectionsFile.empty(updatedAtMs: 5678)
        try await store.write(file)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: configDir.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o700, "Config directory must be owner-only 0700 permissions")
    }

    func testWriteTightensExistingParentDirectoryPermissions() async throws {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        let configDir = payloadURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: configDir.path
        )

        let file = AIConnectionsFile.empty(updatedAtMs: 5678)
        try await store.write(file)

        let attrs = try FileManager.default.attributesOfItem(atPath: configDir.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o700, "Existing config directory permissions must be tightened to 0700")
    }

    func testWriteOverwritesExistingFile() async throws {
        let file1 = AIConnectionsFile.empty(updatedAtMs: 1000)
        try await store.write(file1)

        let file2 = AIConnectionsFile(
            updatedAtMs: 2000,
            lastUsedProviderId: .chatgptCodex,
            providers: [:],
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
            expiresAtMs: 1_700_000_000_000,
        )
        let record = ProviderRecordFile(
            providerId: .chatgptCodex,
            authMethod: .oauth,
            credential: .oauth(oauth),
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: .connected,
                lastVerifiedAtMs: 1_700_000_000_000,
            ),
        )
        let original = AIConnectionsFile(
            updatedAtMs: 1_700_000_000_000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 1_700_000_000_000,
            providers: ["chatgptCodex": record],
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
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        let file = AIConnectionsFile(
            updatedAtMs: 1000,
            lastUsedProviderId: .chatgptCodex,
            lastUsedAtMs: 1000,
            providers: ["chatgptCodex": record],
        )
        try await store.write(file)

        try await store.deleteCredential(for: .chatgptCodex)

        let loaded = try await store.load()
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: payloadURL.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o600, "Deleted file must keep owner-only 0600 permissions")

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
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: fixture.homeURL)
        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("corrupt content".utf8).write(to: payloadURL)

        _ = try await store.load()

        let dirContents = try FileManager.default.contentsOfDirectory(
            at: payloadURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil,
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

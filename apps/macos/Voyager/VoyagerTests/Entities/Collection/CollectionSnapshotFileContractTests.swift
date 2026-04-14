import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotFileContractTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSaveCreatesVoycollPackageAndLoadRoundTrips() async throws {
        let url = makeTemporaryCollectionURL(name: "package-round-trip")
        defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

        let file = VoyagerCollectionFile(
            schemaVersion: 2,
            id: "snapshot-file",
            name: "Snapshot File",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "report",
            scopes: ["/tmp"],
            conditions: [
                .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
            ],
            snapshot: .init(items: [.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantFuture,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: "1.0",
        )

        try await CollectionFileClient.liveValue.save(file, url)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(fileManager.fileExists(atPath: url.appendingPathComponent("collection.plist").path))

        let loaded = try await CollectionFileClient.liveValue.load(url)
        XCTAssertEqual(loaded, file)
    }

    func testLoadLegacySingleFileRoundTrips() async throws {
        let url = makeTemporaryCollectionURL(name: "legacy-single-file")
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: parent) }

        let file = VoyagerCollectionFile(
            schemaVersion: 1,
            id: "legacy-file",
            name: "Legacy File",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let data = try PropertyListEncoder().encode(file)
        try data.write(to: url)

        let loaded = try await CollectionFileClient.liveValue.load(url)
        XCTAssertEqual(loaded, file)
    }

    func testLoadMissingPackagePayloadThrows() async {
        let url = makeTemporaryCollectionURL(name: "missing-payload")
        defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        await XCTAssertThrowsErrorAsync(
            try CollectionFileClient.liveValue.load(url),
        )
    }

    func testEncodeDecodeV2SnapshotFileRoundTrips() throws {
        let file = VoyagerCollectionFile(
            schemaVersion: 2,
            id: "snapshot-file",
            name: "Snapshot File",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "report",
            scopes: ["/tmp"],
            conditions: [
                .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
            ],
            snapshot: .init(items: [.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantFuture,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: "1.0",
        )

        let data = try PropertyListEncoder().encode(file)
        let decoded = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)

        XCTAssertEqual(decoded, file)
    }

    func testDecodeDefinitionOnlyFileLeavesSnapshotNil() throws {
        let file = VoyagerCollectionFile(
            schemaVersion: 1,
            id: "legacy",
            name: "Legacy",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let data = try PropertyListEncoder().encode(file)
        let decoded = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)

        XCTAssertNil(decoded.snapshot)
        XCTAssertNil(decoded.snapshotMeta)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testDecodeDropsMalformedSnapshotInsteadOfFailingWholeFile() throws {
        struct InvalidFile: Codable {
            let schemaVersion: Int
            let id: String
            let name: String
            let createdAt: Date
            let updatedAt: Date
            let query: String
            let scopes: [String]
            let conditions: [CollectionCondition]
            let snapshot: [String: [JSONValue]]
            let snapshotMeta: CollectionSnapshotMeta
            let appVersion: String?
        }

        let invalid = InvalidFile(
            schemaVersion: 2,
            id: "invalid",
            name: "Invalid",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: [],
            conditions: [],
            snapshot: ["items": [.number(1)]],
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantPast,
                itemCount: 1,
                relevanceRoots: [],
            ),
            appVersion: nil,
        )

        let data = try PropertyListEncoder().encode(invalid)
        let decoded = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)

        XCTAssertEqual(decoded.id, invalid.id)
        XCTAssertNil(decoded.snapshot)
        XCTAssertNil(decoded.snapshotMeta)
    }

    func testLoadMalformedSnapshotPackageFallsBackToDefinitionOnly() async throws {
        struct InvalidFile: Codable {
            let schemaVersion: Int
            let id: String
            let name: String
            let createdAt: Date
            let updatedAt: Date
            let query: String
            let scopes: [String]
            let conditions: [CollectionCondition]
            let snapshot: [String: [JSONValue]]
            let snapshotMeta: CollectionSnapshotMeta
            let appVersion: String?
        }

        let url = makeTemporaryCollectionURL(name: "malformed-snapshot-package")
        defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let invalid = InvalidFile(
            schemaVersion: 2,
            id: "invalid-package",
            name: "Invalid Package",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "query",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: ["items": [.number(1)]],
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantPast,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )

        let data = try PropertyListEncoder().encode(invalid)
        try data.write(to: url.appendingPathComponent("collection.plist"))

        let loaded = try await CollectionFileClient.liveValue.load(url)
        XCTAssertEqual(loaded.id, invalid.id)
        XCTAssertEqual(loaded.name, invalid.name)
        XCTAssertNil(loaded.snapshot)
        XCTAssertNil(loaded.snapshotMeta)
    }

    func testEncodeRejectsNonStringSnapshotItems() throws {
        let file = VoyagerCollectionFile(
            schemaVersion: 2,
            id: "invalid-encode",
            name: "Invalid Encode",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: [],
            conditions: [],
            snapshot: .init(items: [.number(1)]),
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantPast,
                itemCount: 1,
                relevanceRoots: [],
            ),
            appVersion: nil,
        )

        XCTAssertThrowsError(try PropertyListEncoder().encode(file))
    }

    private func makeTemporaryCollectionURL(name: String) -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return root.appendingPathComponent("\(name).voycoll")
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> some Any,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in },
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}

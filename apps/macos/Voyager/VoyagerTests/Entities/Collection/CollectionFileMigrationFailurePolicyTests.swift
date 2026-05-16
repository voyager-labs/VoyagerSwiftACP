import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@MainActor
final class CollectionFileFailurePolicyTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMissingSchemaVersionFailsDecode() throws {
        let data = try makeBinaryPlist(MissingSchemaVersionPayload())

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .missingSchemaVersion)
        }
    }

    func testInvalidSchemaVersionTypeFailsDecode() throws {
        let data = try makeBinaryPlist(InvalidSchemaVersionTypePayload())

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .invalidSchemaVersionType)
        }
    }

    func testMissingPackagePayloadThrowsWithoutCreatingPayload() async {
        let url = makeTemporaryCollectionURL(name: "missing-payload-policy")
        defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        do {
            _ = try await CollectionFileClient.liveValue.load(url)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .missingPackagePayload)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: url.appendingPathComponent("collection.plist").path))
    }

    func testUnsupportedFutureVersionSpecKeepsPayloadByteStable() async throws {
        let url = makeTemporaryCollectionURL(name: "future-version")
        defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let payloadURL = url.appendingPathComponent("collection.plist")
        let data = try makeBinaryPlist(
            FutureVersionPayload(
                schemaVersion: 999,
                id: "future",
                name: "Future",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                query: "",
                scopes: ["/tmp"],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
        )
        try data.write(to: payloadURL)

        let beforeData = try Data(contentsOf: payloadURL)

        do {
            _ = try await CollectionFileClient.liveValue.load(url)
            XCTFail("Expected error to be thrown")
        } catch {
            guard case let CollectionFileCompatibilityError.unsupportedFutureSchemaVersion(found, current) = error
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(found, SchemaVersion(legacyInt: 999))
            XCTAssertEqual(current, CollectionFileSchemaVersion.current)
        }

        let afterData = try Data(contentsOf: payloadURL)
        XCTAssertEqual(afterData, beforeData)
    }

    func testCompatibilityOwnerExposesTypedSchemaFailures() throws {
        let missingSchemaData = try makeBinaryPlist(MissingSchemaVersionPayload())
        let legacyMissingSchema = try VoyagerCollectionFileCompatibilityOwner.decode(
            missingSchemaData,
            containerFormat: .legacySingleFile,
        )
        XCTAssertNil(legacyMissingSchema.compatibility.sourceSchemaVersion)
        XCTAssertEqual(
            legacyMissingSchema.compatibility.migrationPath,
            [.legacySingleFileWithoutSchema, .definitionOnlyV1],
        )
        XCTAssertEqual(legacyMissingSchema.file.schemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(legacyMissingSchema.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)

        let invalidSchemaData = try makeBinaryPlist(InvalidSchemaVersionTypePayload())
        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(invalidSchemaData, containerFormat: .legacySingleFile),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .invalidSchemaVersionType)
        }
    }

    func testInvalidDefinitionPayloadThrowsOwnerError() throws {
        let data = try makeBinaryPlist(InvalidDefinitionPayload(
            schemaVersion: 1,
            id: "",
            name: "Broken",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        ))

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .invalidDefinitionPayload)
        }
    }

    func testInvalidPropertyListPayloadThrowsOwnerError() {
        let data = Data("not-a-plist".utf8)

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .invalidPropertyListPayload)
        }
    }

    func testUnrecoverableDocumentCorruptionErrorShapeExists() {
        let data = try? makeBinaryPlist(UnrecoverableCorruptionPayload(
            schemaVersion: 1,
            id: "broken",
            name: "Broken",
            createdAt: "not-a-date",
            updatedAt: "also-not-a-date",
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        ))
        guard let data else {
            return XCTFail("Failed to encode unrecoverable corruption payload")
        }

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .unrecoverableDocumentCorruption)
        }
    }

    func testMalformedSnapshotFallsBackInsteadOfBecomingUnrecoverableCorruption() throws {
        let data = try makeBinaryPlist(InvalidSnapshotPayload(
            schemaVersion: 2,
            id: "corrupt-snapshot",
            name: "Corrupt Snapshot",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "query",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: ["items": [VoyagerShared.JSONValue.number(1)]],
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantPast,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        ))

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertTrue(result.compatibility.usedDefinitionFallback)
        XCTAssertEqual(result.compatibility.warnings, [.droppedMalformedSnapshot])
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
        XCTAssertNil(result.file.snapshot)
        XCTAssertNil(result.file.snapshotMeta)
    }

    func testFutureMinorStructuredVersionShouldBecomeReadOnlyInsteadOfHardFail() throws {
        let data = try makeStructuredSchemaPropertyList(
            schema: ["major": 1, "minor": 2],
            includeSnapshot: true,
            includeSnapshotMeta: true,
        )

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, .init(major: 1, minor: 2))
        XCTAssertEqual(result.compatibility.warnings, [.futureMinorVersionReadOnly])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedFutureMinorVersion)
    }

    private func makeBinaryPlist(_ value: some Encodable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
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

func makeStructuredSchemaPropertyList(
    schema: [String: Int],
    includeSnapshot: Bool,
    includeSnapshotMeta: Bool,
) throws -> Data {
    var payload: [String: Any] = [
        "schemaVersion": schema,
        "id": "structured-version",
        "name": "Structured Version",
        "createdAt": Date.distantPast,
        "updatedAt": Date.distantPast,
        "query": "",
        "scopes": ["/tmp"],
        "conditions": [],
    ]

    if includeSnapshot {
        payload["snapshot"] = [
            "items": ["/tmp/report.txt"],
        ]
    }

    if includeSnapshotMeta {
        payload["snapshotMeta"] = [
            "definitionFingerprint": "fingerprint",
            "capturedAt": Date.distantPast,
            "itemCount": 1,
            "relevanceRoots": ["/tmp"],
        ]
    }

    return try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
}

private struct MissingSchemaVersionPayload: Codable {
    let id = "missing-version"
    let name = "Missing Version"
    let createdAt = Date.distantPast
    let updatedAt = Date.distantPast
    let query = ""
    let scopes = ["/tmp"]
    let conditions: [CollectionCondition] = []
    let appVersion: String? = nil
}

private struct InvalidSchemaVersionTypePayload: Codable {
    let schemaVersion = "two"
    let id = "invalid-version-type"
    let name = "Invalid Version Type"
    let createdAt = Date.distantPast
    let updatedAt = Date.distantPast
    let query = ""
    let scopes = ["/tmp"]
    let conditions: [CollectionCondition] = []
    let appVersion: String? = nil
}

private struct InvalidDefinitionPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let appVersion: String?
}

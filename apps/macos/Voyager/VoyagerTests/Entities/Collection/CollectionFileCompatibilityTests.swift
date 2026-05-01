import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionFileCompatibilityTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCollectionFileCompatibilityMatrix() async throws {
        for matrixCase in makeCompatibilityCases() {
            let url = makeTemporaryCollectionURL(name: matrixCase.name)
            defer { try? fileManager.removeItem(at: url.deletingLastPathComponent()) }

            try matrixCase.writer(url)
            let payloadURL = matrixCase.containerFormat == .package
                ? url.appendingPathComponent("collection.plist")
                : url
            let data = try Data(contentsOf: payloadURL)
            let result = try VoyagerCollectionFileCompatibilityOwner.decode(
                data,
                containerFormat: matrixCase.containerFormat,
            )
            let loaded = try await CollectionFileClient.liveValue.load(url)

            matrixCase.assertLoaded(result, loaded.file)
        }
    }

    func testCurrentSchemaRoundTripEncodingIsStable() throws {
        let file = makeSnapshotFile()

        let data = try makeCompatibilityBinaryPlist(file)
        let decoded = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)
        let reencoded = try makeCompatibilityBinaryPlist(decoded)

        XCTAssertEqual(decoded, file)
        XCTAssertEqual(reencoded, data)
    }

    func testCompatibilityOwnerExposesMalformedSnapshotFallbackMetadata() throws {
        let data = try makeCompatibilityBinaryPlist(makeInvalidSnapshotPayload())

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.current)
        XCTAssertTrue(result.compatibility.usedDefinitionFallback)
        XCTAssertEqual(result.compatibility.warnings, [.droppedMalformedSnapshot])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
        XCTAssertNil(result.file.snapshot)
        XCTAssertNil(result.file.snapshotMeta)
    }

    func testCompatibilityOwnerDropsIncompleteSnapshotPairOnDirectDecodeSuccessPath() throws {
        let data = try makeCompatibilityBinaryPlist(makeSnapshotOnlyPayload())

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertTrue(result.compatibility.usedDefinitionFallback)
        XCTAssertEqual(result.compatibility.warnings, [.droppedIncompleteSnapshotPair])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
        XCTAssertNil(result.file.snapshot)
        XCTAssertNil(result.file.snapshotMeta)
    }

    func testCompatibilityOwnerKeepsDefinitionOnlySnapshotMetaWithZeroItemCount() throws {
        let file = VoyagerCollectionFile(
            id: "definition-only-current",
            name: "Definition Only Current",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantFuture,
                itemCount: 0,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )
        let data = try makeCompatibilityBinaryPlist(file)

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertFalse(result.compatibility.usedDefinitionFallback)
        XCTAssertEqual(result.compatibility.warnings, [])
        XCTAssertTrue(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .allowed)
        XCTAssertNil(result.file.snapshot)
        XCTAssertEqual(result.file.snapshotMeta?.itemCount, 0)
        XCTAssertEqual(result.file.snapshotMeta?.definitionFingerprint, "fingerprint")
    }

    func testCompatibilityOwnerTreatsMissingSchemaAsLegacySingleFileOnly() throws {
        let data = try makeCompatibilityBinaryPlist(makeLegacyNoSchemaPayload())

        let legacyResult = try VoyagerCollectionFileCompatibilityOwner.decode(
            data,
            containerFormat: .legacySingleFile,
        )

        XCTAssertNil(legacyResult.compatibility.sourceSchemaVersion)
        XCTAssertEqual(
            legacyResult.compatibility.migrationPath,
            [.legacySingleFileWithoutSchema, .definitionOnlyV1],
        )
        XCTAssertEqual(legacyResult.file.schemaVersion, .init(major: 1, minor: 0))
        XCTAssertFalse(legacyResult.compatibility.writeBackAllowed)
        XCTAssertEqual(legacyResult.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .missingSchemaVersion)
        }
    }

    func testCurrentSchemaVersionDoesNotDependOnSnapshotPresence() throws {
        let currentDefinitionOnly = VoyagerCollectionFile(
            id: "current-definition-only",
            name: "Current Definition Only",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )
        let currentSnapshot = makeSnapshotFile()

        let definitionResult = try VoyagerCollectionFileCompatibilityOwner.decode(
            makeCompatibilityBinaryPlist(currentDefinitionOnly),
            containerFormat: .package,
        )
        let snapshotResult = try VoyagerCollectionFileCompatibilityOwner.decode(
            makeCompatibilityBinaryPlist(currentSnapshot),
            containerFormat: .package,
        )

        XCTAssertEqual(definitionResult.file.schemaVersion, CollectionFileSchemaVersion.definitionOnlyCurrent)
        XCTAssertEqual(snapshotResult.file.schemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
        XCTAssertEqual(definitionResult.compatibility.migrationPath, [.definitionOnlyV1])
        XCTAssertEqual(snapshotResult.compatibility.migrationPath, [.currentSchemaV2])
        XCTAssertFalse(definitionResult.compatibility.writeBackAllowed)
        XCTAssertTrue(snapshotResult.compatibility.writeBackAllowed)
    }

    func testFailureMatrixExplicitlyDistinguishesFutureAndMalformedCases() throws {
        let futureVersionData = try makeCompatibilityBinaryPlist(makeFutureVersionPayload())
        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(futureVersionData, containerFormat: .package),
        ) { error in
            guard case let CollectionFileCompatibilityError.unsupportedFutureSchemaVersion(found, current) = error
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(found, SchemaVersion(legacyInt: 999))
            XCTAssertEqual(current, CollectionFileSchemaVersion.current)
        }

        let corruptionData = try makeCompatibilityBinaryPlist(makeUnrecoverableCorruptionPayload())
        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(corruptionData, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .unrecoverableDocumentCorruption)
        }
    }

    func testStructuredSchemaVersionObjectShouldDecodeAsAuthoritativeVersion() throws {
        let data = try makeStructuredSchemaPropertyList(
            schema: ["major": 1, "minor": 0],
            includeSnapshot: false,
            includeSnapshotMeta: false,
        )

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(result.file.schemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
        XCTAssertFalse(result.compatibility.usedDefinitionFallback)
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
    }

    func testStructuredVersionShouldOverrideShapeInference() throws {
        let data = try makeStructuredSchemaPropertyList(
            schema: ["major": 1, "minor": 0],
            includeSnapshot: true,
            includeSnapshotMeta: true,
        )

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(result.file.schemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
    }

    private func makeTemporaryCollectionURL(name: String) -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return root.appendingPathComponent("\(name).voycoll")
    }

    private func makeCompatibilityBinaryPlist(_ value: some Encodable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    private func makeFutureVersionPayload() -> FutureVersionPayload {
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
        )
    }

    private func makeUnrecoverableCorruptionPayload() -> UnrecoverableCorruptionPayload {
        UnrecoverableCorruptionPayload(
            schemaVersion: 1,
            id: "broken",
            name: "Broken",
            createdAt: "not-a-date",
            updatedAt: "also-not-a-date",
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        )
    }

    private func makeStructuredSchemaPropertyList(
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
}

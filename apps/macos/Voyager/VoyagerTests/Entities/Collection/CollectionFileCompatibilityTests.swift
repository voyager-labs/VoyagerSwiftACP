import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

/// 컬렉션 파일 호환성 — 스키마/스냅샷 혼합 시 폴백 정책을 검증.
@MainActor
final class CollectionFileCompatibilityTests: XCTestCase {
    let fileManager = FileManager.default

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
            let loadResult = try await CollectionFileClient.liveValue.load(url)

            matrixCase.assertLoaded(result, loadResult.file)
        }
    }

    func testCurrentSchemaRoundTripEncodingIsStable() throws {
        let file = makeSnapshotFile()

        let data = try makeBinaryPlist(file)
        let decoded = try PropertyListDecoder().decode(VoyagerCollectionFile.self, from: data)
        let reencoded = try makeBinaryPlist(decoded)

        XCTAssertEqual(decoded, file)
        XCTAssertEqual(reencoded, data)
    }

    func testCompatibilityOwnerExposesMalformedSnapshotFallbackMetadata() throws {
        let data = try makeBinaryPlist(makeInvalidSnapshotPayload())

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
        let data = try makeBinaryPlist(makeSnapshotOnlyPayload())

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
        let data = try makeBinaryPlist(file)

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
        let data = try makeBinaryPlist(makeLegacyNoSchemaPayload())

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
            makeBinaryPlist(currentDefinitionOnly),
            containerFormat: .package,
        )
        let snapshotResult = try VoyagerCollectionFileCompatibilityOwner.decode(
            makeBinaryPlist(currentSnapshot),
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
        let futureVersionData = try makeBinaryPlist(makeFutureVersionPayload())
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

        let corruptionData = try makeBinaryPlist(makeUnrecoverableCorruptionPayload())
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

        let expectedVersion: SchemaVersion = .init(major: 1, minor: 0)
        XCTAssertEqual(result.compatibility.sourceSchemaVersion, expectedVersion)
        XCTAssertEqual(result.file.schemaVersion, expectedVersion)
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

        let expectedVersion: SchemaVersion = .init(major: 1, minor: 0)
        XCTAssertEqual(result.compatibility.sourceSchemaVersion, expectedVersion)
        XCTAssertEqual(result.file.schemaVersion, expectedVersion)
        XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
        XCTAssertFalse(result.compatibility.writeBackAllowed)
        XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
    }

    func makeBinaryPlist(_ value: some Encodable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    private func makeTemporaryCollectionURL(name: String) -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return root.appendingPathComponent("\(name).voycoll")
    }
}

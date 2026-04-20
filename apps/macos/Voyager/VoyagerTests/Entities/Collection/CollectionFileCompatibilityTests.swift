import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

// swiftlint:disable type_body_length
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

            matrixCase.assertLoaded(result, loaded)
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
            [.legacySingleFileWithoutSchema, .definitionOnlyV1, .currentSchemaV2],
        )
        XCTAssertEqual(legacyResult.file.schemaVersion, CollectionFileSchemaVersion.current)
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

        XCTAssertEqual(definitionResult.file.schemaVersion, CollectionFileSchemaVersion.current)
        XCTAssertEqual(snapshotResult.file.schemaVersion, CollectionFileSchemaVersion.current)
        XCTAssertEqual(definitionResult.compatibility.migrationPath, [.currentSchemaV2])
        XCTAssertEqual(snapshotResult.compatibility.migrationPath, [.currentSchemaV2])
        XCTAssertTrue(definitionResult.compatibility.writeBackAllowed)
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
            XCTAssertEqual(found, 999)
            XCTAssertEqual(current, CollectionFileSchemaVersion.current)
        }

        let corruptionData = try makeBinaryPlist(makeUnrecoverableCorruptionPayload())
        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(corruptionData, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .unrecoverableDocumentCorruption)
        }
    }

    private struct MatrixCase {
        let name: String
        let containerFormat: CollectionFileContainerFormat
        let writer: (URL) throws -> Void
        let assertLoaded: (CollectionFileLoadResult, VoyagerCollectionFile) -> Void
    }

    private func makeCompatibilityCases() -> [MatrixCase] {
        let snapshotFile = makeSnapshotFile()

        return [
            makeLegacySingleFileV1Case(),
            makeLegacySingleFileNoSchemaCase(),
            makeDefinitionOnlyPackageV1Case(),
            makeSnapshotFirstPackageV2Case(snapshotFile: snapshotFile),
            makeCorruptSnapshotFallbackCase(),
            makeSnapshotWithoutMetaCase(),
            makeSnapshotMetaWithoutSnapshotCase(),
        ]
    }

    private func makeLegacySingleFileV1Case() -> MatrixCase {
        .init(
            name: "legacy-single-file-v1",
            containerFormat: .legacySingleFile,
            writer: { url in
                let parent = url.deletingLastPathComponent()
                try self.fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeDefinitionOnlyPayload(schemaVersion: 1))
                try data.write(to: url)
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.containerFormat, .legacySingleFile)
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, 1)
                XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1, .currentSchemaV2])
                XCTAssertFalse(result.compatibility.usedDefinitionFallback)
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
                XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(loaded.id, "definition-only")
                XCTAssertEqual(loaded.name, "Definition Only")
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeLegacySingleFileNoSchemaCase() -> MatrixCase {
        .init(
            name: "legacy-single-file-no-schema",
            containerFormat: .legacySingleFile,
            writer: { url in
                let parent = url.deletingLastPathComponent()
                try self.fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeLegacyNoSchemaPayload())
                try data.write(to: url)
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.containerFormat, .legacySingleFile)
                XCTAssertNil(result.compatibility.sourceSchemaVersion)
                XCTAssertEqual(
                    result.compatibility.migrationPath,
                    [.legacySingleFileWithoutSchema, .definitionOnlyV1, .currentSchemaV2],
                )
                XCTAssertFalse(result.compatibility.usedDefinitionFallback)
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
                XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(loaded.id, "legacy-no-schema")
                XCTAssertEqual(loaded.name, "Legacy No Schema")
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeDefinitionOnlyPackageV1Case() -> MatrixCase {
        .init(
            name: "definition-only-package-v1",
            containerFormat: .package,
            writer: { url in
                try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeDefinitionOnlyPayload(schemaVersion: 1))
                try data.write(to: url.appendingPathComponent("collection.plist"))
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.containerFormat, .package)
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, 1)
                XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1, .currentSchemaV2])
                XCTAssertFalse(result.compatibility.usedDefinitionFallback)
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
                XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(loaded.id, "definition-only")
                XCTAssertEqual(loaded.name, "Definition Only")
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeSnapshotFirstPackageV2Case(snapshotFile: VoyagerCollectionFile) -> MatrixCase {
        .init(
            name: "snapshot-first-package-v2",
            containerFormat: .package,
            writer: { url in
                try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(snapshotFile)
                try data.write(to: url.appendingPathComponent("collection.plist"))
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.containerFormat, .package)
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(result.compatibility.migrationPath, [.currentSchemaV2])
                XCTAssertFalse(result.compatibility.usedDefinitionFallback)
                XCTAssertTrue(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .allowed)
                XCTAssertEqual(loaded, snapshotFile)
                XCTAssertEqual(loaded.snapshot?.items, [VoyagerShared.JSONValue.string("/tmp/report.txt")])
                XCTAssertEqual(loaded.snapshotMeta?.definitionFingerprint, "fingerprint")
            },
        )
    }

    private func makeCorruptSnapshotFallbackCase() -> MatrixCase {
        .init(
            name: "corrupt-snapshot-valid-definition-package",
            containerFormat: .package,
            writer: { url in
                try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeInvalidSnapshotPayload())
                try data.write(to: url.appendingPathComponent("collection.plist"))
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.containerFormat, .package)
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(
                    result.compatibility.migrationPath,
                    [.currentSchemaV2, .definitionFallbackFromMalformedSnapshot],
                )
                XCTAssertTrue(result.compatibility.usedDefinitionFallback)
                XCTAssertEqual(result.compatibility.warnings, [.droppedMalformedSnapshot])
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
                XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(loaded.id, "corrupt-snapshot")
                XCTAssertEqual(loaded.name, "Corrupt Snapshot")
                XCTAssertEqual(loaded.query, "query")
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeSnapshotWithoutMetaCase() -> MatrixCase {
        .init(
            name: "snapshot-without-meta-package",
            containerFormat: .package,
            writer: { url in
                try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeSnapshotOnlyPayload())
                try data.write(to: url.appendingPathComponent("collection.plist"))
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(
                    result.compatibility.migrationPath,
                    [.currentSchemaV2, .definitionFallbackFromIncompletePair],
                )
                XCTAssertTrue(result.compatibility.usedDefinitionFallback)
                XCTAssertEqual(result.compatibility.warnings, [.droppedIncompleteSnapshotPair])
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeSnapshotMetaWithoutSnapshotCase() -> MatrixCase {
        .init(
            name: "meta-without-snapshot-package",
            containerFormat: .package,
            writer: { url in
                try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                let data = try self.makeBinaryPlist(self.makeSnapshotMetaOnlyPayload())
                try data.write(to: url.appendingPathComponent("collection.plist"))
            },
            assertLoaded: { result, loaded in
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.current)
                XCTAssertEqual(
                    result.compatibility.migrationPath,
                    [.currentSchemaV2, .definitionFallbackFromIncompletePair],
                )
                XCTAssertTrue(result.compatibility.usedDefinitionFallback)
                XCTAssertEqual(result.compatibility.warnings, [.droppedIncompleteSnapshotPair])
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
                XCTAssertNil(loaded.snapshot)
                XCTAssertNil(loaded.snapshotMeta)
            },
        )
    }

    private func makeSnapshotFile() -> VoyagerCollectionFile {
        VoyagerCollectionFile(
            id: "snapshot-v2",
            name: "Snapshot V2",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "report",
            scopes: ["/tmp"],
            conditions: [
                .init(
                    propertyKey: "name_full",
                    operatorCode: "eq",
                    value: VoyagerShared.JSONValue.string("report"),
                ),
            ],
            snapshot: .init(items: [
                VoyagerShared.JSONValue.string("/tmp/report.txt"),
            ]),
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantFuture,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: "1.0",
        )
    }

    private func makeDefinitionOnlyPayload(schemaVersion: Int) -> LegacyDefinitionOnlyPayload {
        LegacyDefinitionOnlyPayload(
            schemaVersion: schemaVersion,
            id: "definition-only",
            name: "Definition Only",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        )
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

    private func makeLegacyNoSchemaPayload() -> LegacyNoSchemaPayload {
        LegacyNoSchemaPayload(
            id: "legacy-no-schema",
            name: "Legacy No Schema",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        )
    }

    private func makeInvalidSnapshotPayload() -> InvalidSnapshotPayload {
        InvalidSnapshotPayload(
            schemaVersion: CollectionFileSchemaVersion.current,
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
        )
    }

    private func makeSnapshotOnlyPayload() -> SnapshotOnlyPayload {
        SnapshotOnlyPayload(
            schemaVersion: CollectionFileSchemaVersion.current,
            id: "snapshot-only",
            name: "Snapshot Only",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: .init(items: [
                VoyagerShared.JSONValue.string("/tmp/report.txt"),
            ]),
            appVersion: nil,
        )
    }

    private func makeSnapshotMetaOnlyPayload() -> SnapshotMetaOnlyPayload {
        SnapshotMetaOnlyPayload(
            schemaVersion: CollectionFileSchemaVersion.current,
            id: "snapshot-meta-only",
            name: "Snapshot Meta Only",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantPast,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )
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
}

// swiftlint:enable type_body_length

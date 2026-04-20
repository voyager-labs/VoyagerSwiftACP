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

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
        XCTAssertEqual(legacyResult.file.schemaVersion, VoyagerCollectionFile.currentSchemaVersion)
        XCTAssertFalse(legacyResult.compatibility.writeBackAllowed)
        XCTAssertEqual(legacyResult.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)

        XCTAssertThrowsError(
            try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package),
        ) { error in
            XCTAssertEqual(error as? CollectionFileCompatibilityError, .missingSchemaVersion)
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
                XCTAssertEqual(loaded.schemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(loaded.schemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(loaded.schemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, VoyagerCollectionFile.currentSchemaVersion)
                XCTAssertEqual(
                    result.compatibility.migrationPath,
                    [.currentSchemaV2, .definitionFallbackFromMalformedSnapshot],
                )
                XCTAssertTrue(result.compatibility.usedDefinitionFallback)
                XCTAssertEqual(result.compatibility.warnings, [.droppedMalformedSnapshot])
                XCTAssertFalse(result.compatibility.writeBackAllowed)
                XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
                XCTAssertEqual(loaded.schemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
                XCTAssertEqual(result.compatibility.sourceSchemaVersion, VoyagerCollectionFile.currentSchemaVersion)
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
            schemaVersion: VoyagerCollectionFile.currentSchemaVersion,
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
            schemaVersion: VoyagerCollectionFile.currentSchemaVersion,
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
            schemaVersion: VoyagerCollectionFile.currentSchemaVersion,
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

private struct LegacyDefinitionOnlyPayload: Codable {
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

private struct LegacyNoSchemaPayload: Codable {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let appVersion: String?
}

private struct InvalidSnapshotPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: [String: [VoyagerShared.JSONValue]]
    let snapshotMeta: CollectionSnapshotMeta
    let appVersion: String?
}

private struct SnapshotOnlyPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshot: CollectionPersistedSnapshot
    let appVersion: String?
}

private struct SnapshotMetaOnlyPayload: Codable {
    let schemaVersion: Int
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let query: String
    let scopes: [String]
    let conditions: [CollectionCondition]
    let snapshotMeta: CollectionSnapshotMeta
    let appVersion: String?
}

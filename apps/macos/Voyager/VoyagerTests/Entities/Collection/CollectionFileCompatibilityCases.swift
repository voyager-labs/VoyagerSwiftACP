import Foundation
import VoyagerShared

// swiftlint:disable multiline_arguments

extension CollectionFileCompatibilityTests {
    struct MatrixCase {
        let name: String
        let containerFormat: CollectionFileContainerFormat
        let writer: (URL) throws -> Void
        let assertLoaded: (CollectionFileLoadResult, VoyagerCollectionFile) -> Void
    }

    func makeCompatibilityCases() -> [MatrixCase] {
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

    func makeLegacySingleFileV1Case() -> MatrixCase {
        .init(name: "legacy-single-file-v1", containerFormat: .legacySingleFile, writer: { url in
            let parent = url.deletingLastPathComponent()
            try self.fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeDefinitionOnlyPayload(schemaVersion: 1))
            try data.write(to: url)
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.containerFormat, .legacySingleFile)
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, SchemaVersion(legacyInt: 1))
            XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
            XCTAssertFalse(result.compatibility.usedDefinitionFallback)
            XCTAssertFalse(result.compatibility.writeBackAllowed)
            XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
            XCTAssertEqual(loaded.schemaVersion, .init(major: 1, minor: 0))
            XCTAssertEqual(loaded.id, "definition-only")
            XCTAssertEqual(loaded.name, "Definition Only")
            XCTAssertNil(loaded.snapshot)
            XCTAssertNil(loaded.snapshotMeta)
        })
    }

    func makeLegacySingleFileNoSchemaCase() -> MatrixCase {
        .init(name: "legacy-single-file-no-schema", containerFormat: .legacySingleFile, writer: { url in
            let parent = url.deletingLastPathComponent()
            try self.fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeLegacyNoSchemaPayload())
            try data.write(to: url)
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.containerFormat, .legacySingleFile)
            XCTAssertNil(result.compatibility.sourceSchemaVersion)
            XCTAssertEqual(result.compatibility.migrationPath, [.legacySingleFileWithoutSchema, .definitionOnlyV1])
            XCTAssertFalse(result.compatibility.usedDefinitionFallback)
            XCTAssertFalse(result.compatibility.writeBackAllowed)
            XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
            XCTAssertEqual(loaded.schemaVersion, .init(major: 1, minor: 0))
            XCTAssertEqual(loaded.id, "legacy-no-schema")
            XCTAssertEqual(loaded.name, "Legacy No Schema")
            XCTAssertNil(loaded.snapshot)
            XCTAssertNil(loaded.snapshotMeta)
        })
    }

    func makeDefinitionOnlyPackageV1Case() -> MatrixCase {
        .init(name: "definition-only-package-v1", containerFormat: .package, writer: { url in
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeDefinitionOnlyPayload(schemaVersion: 1))
            try data.write(to: url.appendingPathComponent("collection.plist"))
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.containerFormat, .package)
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, SchemaVersion(legacyInt: 1))
            XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
            XCTAssertFalse(result.compatibility.usedDefinitionFallback)
            XCTAssertFalse(result.compatibility.writeBackAllowed)
            XCTAssertEqual(result.compatibility.writeBackReason, .blockedLegacyVersionUpgrade)
            XCTAssertEqual(loaded.schemaVersion, .init(major: 1, minor: 0))
            XCTAssertEqual(loaded.id, "definition-only")
            XCTAssertEqual(loaded.name, "Definition Only")
            XCTAssertNil(loaded.snapshot)
            XCTAssertNil(loaded.snapshotMeta)
        })
    }

    func makeSnapshotFirstPackageV2Case(snapshotFile: VoyagerCollectionFile) -> MatrixCase {
        .init(name: "snapshot-first-package-v2", containerFormat: .package, writer: { url in
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(snapshotFile)
            try data.write(to: url.appendingPathComponent("collection.plist"))
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.containerFormat, .package)
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
            XCTAssertEqual(result.compatibility.migrationPath, [.currentSchemaV2])
            XCTAssertFalse(result.compatibility.usedDefinitionFallback)
            XCTAssertTrue(result.compatibility.writeBackAllowed)
            XCTAssertEqual(result.compatibility.writeBackReason, .allowed)
            XCTAssertEqual(loaded, snapshotFile)
            XCTAssertEqual(loaded.snapshot?.items, [VoyagerShared.JSONValue.string("/tmp/report.txt")])
            XCTAssertEqual(loaded.snapshotMeta?.definitionFingerprint, "fingerprint")
        })
    }

    func makeCorruptSnapshotFallbackCase() -> MatrixCase {
        .init(name: "corrupt-snapshot-valid-definition-package", containerFormat: .package, writer: { url in
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeInvalidSnapshotPayload())
            try data.write(to: url.appendingPathComponent("collection.plist"))
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.containerFormat, .package)
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
            XCTAssertEqual(
                result.compatibility.migrationPath,
                [.currentSchemaV2, .definitionFallbackFromMalformedSnapshot],
            )
            XCTAssertTrue(result.compatibility.usedDefinitionFallback)
            XCTAssertEqual(result.compatibility.warnings, [.droppedMalformedSnapshot])
            XCTAssertFalse(result.compatibility.writeBackAllowed)
            XCTAssertEqual(result.compatibility.writeBackReason, .blockedDefinitionFallback)
            XCTAssertEqual(loaded.schemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
            XCTAssertEqual(loaded.id, "corrupt-snapshot")
            XCTAssertEqual(loaded.name, "Corrupt Snapshot")
            XCTAssertEqual(loaded.query, "query")
            XCTAssertNil(loaded.snapshot)
            XCTAssertNil(loaded.snapshotMeta)
        })
    }

    func makeSnapshotWithoutMetaCase() -> MatrixCase {
        .init(name: "snapshot-without-meta-package", containerFormat: .package, writer: { url in
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeSnapshotOnlyPayload())
            try data.write(to: url.appendingPathComponent("collection.plist"))
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
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
        })
    }

    func makeSnapshotMetaWithoutSnapshotCase() -> MatrixCase {
        .init(name: "meta-without-snapshot-package", containerFormat: .package, writer: { url in
            try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try self.makeBinaryPlist(self.makeSnapshotMetaOnlyPayload())
            try data.write(to: url.appendingPathComponent("collection.plist"))
        }, assertLoaded: { result, loaded in
            XCTAssertEqual(result.compatibility.sourceSchemaVersion, CollectionFileSchemaVersion.snapshotBearingCurrent)
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
        })
    }

    func makeSnapshotFile() -> VoyagerCollectionFile {
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
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: "fingerprint",
                capturedAt: .distantFuture,
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: "1.0",
        )
    }

    func makeDefinitionOnlyPayload(schemaVersion: Int) -> LegacyDefinitionOnlyPayload {
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

    func makeFutureVersionPayload() -> FutureVersionPayload {
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

    func makeUnrecoverableCorruptionPayload() -> UnrecoverableCorruptionPayload {
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

    func makeLegacyNoSchemaPayload() -> LegacyNoSchemaPayload {
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

    func makeInvalidSnapshotPayload() -> InvalidSnapshotPayload {
        InvalidSnapshotPayload(
            schemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
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

    func makeSnapshotOnlyPayload() -> SnapshotOnlyPayload {
        SnapshotOnlyPayload(
            schemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
            id: "snapshot-only",
            name: "Snapshot Only",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            appVersion: nil,
        )
    }

    func makeSnapshotMetaOnlyPayload() -> SnapshotMetaOnlyPayload {
        SnapshotMetaOnlyPayload(
            schemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
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
}

// swiftlint:enable multiline_arguments

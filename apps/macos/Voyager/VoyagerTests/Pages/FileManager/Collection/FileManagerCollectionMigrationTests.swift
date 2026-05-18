import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class FileManagerCollectionMigrationTests: XCTestCase {
    func testResolveCollectionFiltersMigratesLegacyConditions() {
        let file = VoyagerCollectionFile(
            id: "legacy",
            name: "Legacy",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [
                CollectionCondition(propertyKey: "name", operatorCode: "eq", value: .string("Report")),
                CollectionCondition(propertyKey: "file_allocated_size", operatorCode: "eq", value: .number(12)),
            ],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let resolved = CollectionFilterResolution.resolve(
            file: file,
            registryClient: RegistryTestSupport.makeRegistryClient(),
        )

        XCTAssertEqual(resolved.conditions.map(\.propertyKey), ["name_full", "size"])
        XCTAssertTrue(resolved.conditions.allSatisfy(\.isActive))
    }

    func testLegacyDefinitionOnlyFileHasNoUsableSnapshot() {
        let file = VoyagerCollectionFile(
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

        XCTAssertNil(CollectionSnapshotHydration.usableSnapshot(for: file))
        XCTAssertNil(CollectionSnapshotHydration.syntheticSearchResponse(for: file))
    }

    func testCompatibilityOwnerMigratesLegacyDefinitionOnlyPayloadToCurrentSemanticModel() throws {
        struct LegacyDefinitionOnlyPayload: Codable {
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

        let payload = LegacyDefinitionOnlyPayload(
            schemaVersion: 1,
            id: "legacy",
            name: "Legacy",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [],
            appVersion: nil,
        )
        let data = try PropertyListEncoder().encode(payload)

        let result = try VoyagerCollectionFileCompatibilityOwner.decode(data, containerFormat: .package)

        XCTAssertEqual(result.compatibility.sourceSchemaVersion, .init(major: 1, minor: 0))
        XCTAssertEqual(result.compatibility.migrationPath, [.definitionOnlyV1])
        XCTAssertEqual(result.file.schemaVersion, .init(major: 1, minor: 0))
        XCTAssertNil(result.file.snapshot)
        XCTAssertNil(result.file.snapshotMeta)
        XCTAssertNil(CollectionSnapshotHydration.usableSnapshot(for: result.file))
        XCTAssertNil(CollectionSnapshotHydration.syntheticSearchResponse(for: result.file))
    }
}

import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManager collection 마이그레이션이 schema/version/contracts를 보존하며 동작하는지 검증한다.
@MainActor
final class FileManagerCollectionMigrationTests: XCTestCase {
    /// testResolveCollectionFiltersMigratesLegacyConditions 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

        let resolved = file.resolveCollectionFilters(
            registryClient: RegistryTestSupport.makeRegistryClient(),
        )

        XCTAssertEqual(resolved.conditions.map(\.propertyKey), ["name_full", "size"])
        XCTAssertTrue(resolved.conditions.allSatisfy(\.isActive))
    }

    /// testLegacyDefinitionOnlyFileHasNoUsableSnapshot 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testCompatibilityOwnerMigratesLegacyDefinitionOnlyPayloadToCurrentSemanticModel 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

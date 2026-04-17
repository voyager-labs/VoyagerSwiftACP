import Foundation
@testable import Voyager
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

        let resolved = file.resolveCollectionFilters(
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
}

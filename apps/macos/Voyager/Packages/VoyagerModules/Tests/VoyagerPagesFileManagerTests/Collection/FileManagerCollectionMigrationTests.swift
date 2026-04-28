import Foundation
@testable import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerCollectionMigrationTests: XCTestCase {
    func testResolveCollectionFiltersMigratesLegacyConditions() {
        let file = VoyagerCollectionFile(
            schemaVersion: 1,
            id: "legacy",
            name: "Legacy",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [
                VoyagerCollectionFile.CollectionCondition(
                    propertyKey: "name",
                    operatorCode: "eq",
                    value: .string("Report"),
                ),
                VoyagerCollectionFile.CollectionCondition(
                    propertyKey: "file_allocated_size",
                    operatorCode: "eq",
                    value: .number(12),
                ),
            ],
            appVersion: nil,
        )

        let resolved = file.resolveCollectionFilters(
            registryClient: Self.makeRegistryClient(),
        )

        XCTAssertEqual(resolved.conditions.map(\.propertyKey), ["name_full", "size"])
        XCTAssertTrue(resolved.conditions.allSatisfy(\.isActive))
    }

    private nonisolated static func makeRegistryClient() -> VoyagerEntitiesEntry.RegistryClient {
        let resolution = resolvePropertyKey(for:)
        return VoyagerEntitiesEntry.RegistryClient(
            allProperties: { [] },
            labelForKey: { $0 },
            propertyTypeString: { _ in "string" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { _ in
                VoyagerEntitiesEntry.OperatorDefinition(
                    uiLabel: "Equals",
                    mdqueryOperator: nil as String?,
                    valueShape: nil as VoyagerEntitiesEntry.ValueShape?,
                    valueCount: nil as VoyagerEntitiesEntry.ValueCount?,
                    allowedTypes: nil as [String]?,
                    inverseOf: nil as String?,
                    aliases: nil as [String]?,
                    uiValueKind: nil as [String: String]?,
                )
            },
            operatorValueUIKind: { _, _ in "singleText" },
            resolvePropertyKey: resolution,
        )
    }

    private nonisolated static func resolvePropertyKey(for key: String) -> VoyagerEntitiesEntry.PropertyKeyResolution {
        switch key {
        case "name_full":
            .canonical(key)
        case "size":
            .canonical(key)
        case "file_allocated_size":
            .legacy(original: key, normalized: "size")
        case "name":
            .legacy(original: key, normalized: "name_full")
        default:
            .unknown(key)
        }
    }
}

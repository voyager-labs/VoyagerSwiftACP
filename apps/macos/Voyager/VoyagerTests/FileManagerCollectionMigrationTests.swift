import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerCollectionMigrationTests: XCTestCase {
    func testOpenCollectionFileMigratesLegacyConditions() async {
        let file = VoyagerCollectionFile(
            schemaVersion: 1,
            id: "legacy",
            name: "Legacy",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            query: "",
            scopes: ["/tmp"],
            conditions: [
                CollectionCondition(propertyKey: "name", operatorCode: "eq", value: .string("Report")),
                CollectionCondition(propertyKey: "size", operatorCode: "eq", value: .number(12)),
            ],
            sortKey: nil,
            sortOrder: nil,
            viewLayout: nil,
            appVersion: nil,
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { _, _ in },
                load: { _ in file },
            )
            $0.registryClient = makeRegistryClient()
            $0.searchClient = SearchClient(
                search: { _ in kEmptySearchResponse },
                applyFilters: { _ in kEmptySearchResponse },
            )
        }
        store.exhaustivity = .off

        let url = URL(fileURLWithPath: "/tmp/legacy.voycoll")
        await store.send(.openCollectionFile(url))
        await store.receive(\.collectionFileLoaded)

        XCTAssertEqual(
            store.state.composer.conditions.map(\.propertyKey),
            ["name_full", "file_allocated_size"],
        )
        XCTAssertTrue(store.state.composer.conditions.allSatisfy(\.isActive))
    }
}

private let kRegistryLabels: [String: String] = [
    "name_full": "Name",
    "file_allocated_size": "Size",
]

private let kRegistryOperatorDefinition = OperatorDefinition(
    uiLabel: "Equals",
    mdqueryOperator: nil as String?,
    valueShape: nil as ValueShape?,
    valueCount: nil as ValueCount?,
    allowedTypes: nil as [String]?,
    inverseOf: nil as String?,
    aliases: nil as [String]?,
    uiValueKind: [
        "string": "singleText",
        "number": "singleNumber",
        "date": "singleDate",
        "boolean": "toggle",
    ] as [String: String]?,
)

private let kEmptySearchResponse = SearchResponsePayload(
    itemCount: 0,
    appliedFilters: nil,
    items: nil,
    error: nil,
)

private func makeRegistryClient() -> RegistryClient {
    RegistryClient(
        allProperties: { [] },
        labelForKey: { kRegistryLabels[$0] ?? $0 },
        propertyTypeString: registryPropertyType,
        operatorCodes: { _ in ["eq"] },
        operatorDefinition: { _ in kRegistryOperatorDefinition },
        operatorValueUIKind: { _, typeKey in registryUIKind(for: typeKey) },
        resolvePropertyKey: registryResolution,
    )
}

private func registryPropertyType(for key: String) -> String {
    switch key {
    case "file_allocated_size":
        "number"
    default:
        "string"
    }
}

private func registryUIKind(for typeKey: String) -> String {
    switch typeKey {
    case "number":
        "singleNumber"
    case "date":
        "singleDate"
    case "boolean":
        "toggle"
    default:
        "singleText"
    }
}

private func registryResolution(for key: String) -> PropertyKeyResolution {
    switch key {
    case "name_full":
        .canonical(key)
    case "file_allocated_size":
        .canonical(key)
    case "name":
        .legacy(original: key, normalized: "name_full")
    case "size":
        .legacy(original: key, normalized: "file_allocated_size")
    default:
        .unknown(key)
    }
}

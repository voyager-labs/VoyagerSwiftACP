import Foundation

import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class CollectionFeatureTests: XCTestCase {
    func testResolveDetailedMapsLegacyKeysAndUnknowns() {
        let registryClient = makeRegistryClient()
        let appliedFilters = AppliedFiltersPayload(
            scopes: ["/tmp"],
            conditions: [
                .init(propertyKey: "name", operator: "eq", value: .string("report")),
                .init(propertyKey: "legacy_key", operator: "eq", value: .string("legacy")),
            ],
        )

        let resolved = AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: [],
            fallbackConditions: [],
            registryClient: registryClient,
        )

        XCTAssertEqual(resolved.scopes, ["/tmp"])
        XCTAssertEqual(resolved.unknownKeys, ["legacy_key"])
        XCTAssertEqual(resolved.conditions.count, 2)

        let legacyCondition = resolved.conditions[0]
        XCTAssertEqual(legacyCondition.propertyKey, "name_full")
        XCTAssertEqual(legacyCondition.propertyLabel, "Name")
        XCTAssertEqual(legacyCondition.operatorLabel, "Equals")
        XCTAssertEqual(legacyCondition.values, ["report"])
        XCTAssertTrue(legacyCondition.isActive)

        let unknownCondition = resolved.conditions[1]
        XCTAssertEqual(unknownCondition.propertyKey, "legacy_key")
        XCTAssertEqual(unknownCondition.propertyLabel, "Unknown (legacy_key)")
        XCTAssertEqual(unknownCondition.operatorLabel, "eq")
        XCTAssertEqual(unknownCondition.values, ["legacy"])
        XCTAssertFalse(unknownCondition.isActive)
    }

    func testApplyFiltersSkipsInactiveConditions() async {
        let recorder = FiltersRecorder()
        let conditions = [makeActiveCondition(), makeInactiveCondition()]
        let store = makeComposerStore(recorder: recorder, conditions: conditions)

        await runApplyFiltersTest(store: store)

        let payload = await recorder.last()
        XCTAssertEqual(payload?.conditions.count, 1)
        XCTAssertEqual(payload?.conditions.first?.propertyKey, "name_full")
    }

    func testSaveToExistingOmitsInactiveConditions() async {
        let recorder = SavedCollectionsRecorder()
        let payload = makeSavePayload(conditions: [makeActiveCondition(), makeInactiveCondition()])
        let url = URL(fileURLWithPath: "/tmp/collection")
        let store = makeCollectionStore(recorder: recorder)

        await runSaveToExistingTest(store: store, payload: payload, url: url)

        let saved = await recorder.last()
        XCTAssertEqual(saved?.file.conditions.count, 1)
        XCTAssertEqual(saved?.file.conditions.first?.propertyKey, "name_full")
        XCTAssertEqual(saved?.url.pathExtension, "voycoll")
    }
}

private let kRegistryLabels: [String: String] = [
    "name_full": "Name",
    "file_allocated_size": "Size",
]

private let kRegistryOperatorDefinition = OperatorDefinition(
    uiLabel: "Equals",
    mdqueryOperator: nil,
    valueShape: nil,
    valueCount: nil,
    allowedTypes: nil,
    inverseOf: nil,
    aliases: nil,
    uiValueKind: [
        "string": "singleText",
        "number": "singleNumber",
        "date": "singleDate",
        "boolean": "toggle",
    ],
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
    case "name":
        .legacy(original: key, normalized: "name_full")
    case "size":
        .legacy(original: key, normalized: "file_allocated_size")
    default:
        .unknown(key)
    }
}

private func makeActiveCondition() -> Condition {
    Condition(
        propertyKey: "name_full",
        propertyLabel: "Name",
        propertyType: "string",
        operatorCode: "eq",
        operatorLabel: "Equals",
        operatorValueArity: 1,
        operatorValueUIKind: "singleText",
        valueType: "string",
        values: ["Report"],
        isActive: true,
    )
}

private func makeInactiveCondition() -> Condition {
    Condition(
        propertyKey: "legacy_key",
        propertyLabel: "Unknown (legacy_key)",
        propertyType: "unknown",
        operatorCode: "eq",
        operatorLabel: "eq",
        operatorValueArity: nil,
        operatorValueUIKind: nil,
        valueType: "unknown",
        values: ["Legacy"],
        isActive: false,
    )
}

@MainActor
private func makeComposerStore(
    recorder: FiltersRecorder,
    conditions: [Condition],
) -> TestStore<ComposerFeature.State, ComposerFeature.Action> {
    let searchClient = SearchClient(
        search: { _ in kEmptySearchResponse },
        applyFilters: { request in
            await recorder.append(request.filters)
            return kEmptySearchResponse
        },
    )

    let store = TestStore(initialState: {
        var state = ComposerFeature.State()
        state.scopes = ["/tmp"]
        state.conditions = conditions
        return state
    }()) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = searchClient
    }

    store.exhaustivity = .off
    return store
}

@MainActor
private func runApplyFiltersTest(
    store: TestStore<ComposerFeature.State, ComposerFeature.Action>,
) async {
    await store.send(.applyFilters)
    await store.receive(\.filtersResponse)
    await store.finish()
}

private func makeSavePayload(conditions: [Condition]) -> SaveRequestPayload {
    SaveRequestPayload(
        context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: conditions),
        isSearchLoading: false,
        isFiltersLoading: false,
    )
}

@MainActor
private func makeCollectionStore(
    recorder: SavedCollectionsRecorder,
) -> TestStore<CollectionFeature.State, CollectionFeature.Action> {
    let collectionFileClient = CollectionFileClient(
        save: { file, url in
            await recorder.append(file: file, url: url)
        },
        load: { _ in kEmptyCollectionFile },
    )
    let store = TestStore(initialState: CollectionFeature.State()) {
        CollectionFeature()
    } withDependencies: {
        $0.collectionFileClient = collectionFileClient
        $0.userDefaultsClient = .testValue
    }
    store.exhaustivity = .off
    return store
}

@MainActor
private func runSaveToExistingTest(
    store: TestStore<CollectionFeature.State, CollectionFeature.Action>,
    payload: SaveRequestPayload,
    url: URL,
) async {
    await store.send(.saveToExisting(payload, url))
    await store.receive(\.saveCompleted)
    await store.finish()
}

private let kEmptySearchResponse = SearchResponsePayload(
    itemCount: 0,
    appliedFilters: nil,
    items: nil,
    error: nil,
)

private let kEmptyCollectionFile = VoyagerCollectionFile(
    schemaVersion: 1,
    id: "",
    name: "",
    createdAt: .distantPast,
    updatedAt: .distantPast,
    query: "",
    scopes: [],
    conditions: [],
    appVersion: nil,
)

private actor FiltersRecorder {
    private var payloads: [SearchFiltersPayload] = []

    func append(_ payload: SearchFiltersPayload) {
        payloads.append(payload)
    }

    func last() -> SearchFiltersPayload? {
        payloads.last
    }
}

private actor SavedCollectionsRecorder {
    struct Entry {
        let file: VoyagerCollectionFile
        let url: URL
    }

    private var entries: [Entry] = []

    func append(file: VoyagerCollectionFile, url: URL) {
        entries.append(Entry(file: file, url: url))
    }

    func last() -> Entry? {
        entries.last
    }
}

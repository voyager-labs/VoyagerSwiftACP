// swiftlint:disable file_length
import Foundation

import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
@testable import VoyagerShared
import XCTest

@MainActor
final class CollectionFeatureTests: XCTestCase {
    func testResolveDetailedMapsLegacyKeysAndUnknowns() {
        let registryClient = makeRegistryClient()
        let appliedFilters = AppliedFiltersPayload(
            scopes: ["/tmp"],
            conditions: [
                .init(propertyKey: "name", operator: "eq", value: VoyagerShared.JSONValue.string("report")),
                .init(propertyKey: "legacy_key", operator: "eq", value: VoyagerShared.JSONValue.string("legacy")),
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

    func testResolveDetailedRestoresDateRangePayloadWithoutShapeLoss() {
        let registryClient = makeRangeDateRegistryClient()
        let appliedFilters = AppliedFiltersPayload(
            scopes: ["/tmp"],
            conditions: [
                .init(
                    propertyKey: "content_modified_at",
                    operator: "btw",
                    value: VoyagerShared.JSONValue.array([.string("2026-02-26"), .string("2026-02-27")]),
                ),
            ],
        )

        let resolved = AppliedFiltersUtils.resolveDetailed(
            appliedFilters,
            fallbackScopes: [],
            fallbackConditions: [],
            registryClient: registryClient,
        )

        XCTAssertEqual(resolved.unknownKeys, [])
        XCTAssertEqual(resolved.conditions.count, 1)
        XCTAssertEqual(resolved.conditions[0].operatorCode, "btw")
        XCTAssertEqual(resolved.conditions[0].operatorValueUIKind, "rangeDate")
        XCTAssertEqual(resolved.conditions[0].operatorValueArity, 2)
        XCTAssertEqual(resolved.conditions[0].values, ["2026-02-26", "2026-02-27"])
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

    func testSetOperatorUpdatesInputContractArityForSingleRangeAndNone() async {
        let recorder = FiltersRecorder()
        let conditions = [makeNumberCondition(values: ["10"])]
        let store = makeComposerStore(
            recorder: recorder,
            conditions: conditions,
            registryClient: makeOperatorContractRegistryClient(),
        )

        await store.send(.setOperator(propertyKey: "size", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Is between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeNumber"
            $0.conditions[0].valueType = "number"
            $0.conditions[0].values = nil
        }

        await store.send(.setOperator(propertyKey: "size", operatorCode: "eq")) {
            $0.conditions[0].operatorCode = "eq"
            $0.conditions[0].operatorLabel = "Is"
            $0.conditions[0].operatorValueArity = 1
            $0.conditions[0].operatorValueUIKind = "singleNumber"
            $0.conditions[0].valueType = "number"
            $0.conditions[0].values = nil
        }

        await store.send(.setOperator(propertyKey: "size", operatorCode: "exists")) {
            $0.isLoadingFilters = true
            $0.isFilteringInFlight = true
            $0.conditions[0].operatorCode = "exists"
            $0.conditions[0].operatorLabel = "Exists"
            $0.conditions[0].operatorValueArity = 0
            $0.conditions[0].operatorValueUIKind = "none"
            $0.conditions[0].valueType = "string"
            $0.conditions[0].values = []
        }
        await store.receive(\.internal.filtersResponse) {
            $0.isLoadingFilters = false
            $0.isFilteringInFlight = false
            $0.lastFiltersResponse = kEmptySearchResponse
        }

        let payload = await recorder.last()
        XCTAssertEqual(payload?.conditions.count, 1)
        XCTAssertEqual(payload?.conditions.first?.propertyKey, "size")
        XCTAssertEqual(payload?.conditions.first?.operator, "exists")
        XCTAssertNil(payload?.conditions.first?.value)
    }

    func testSetOperatorClearsStaleValuesOnSameConditionSwitchSequence() async {
        let recorder = FiltersRecorder()
        let conditions = [makeNumberCondition(values: ["10", "20"])]
        let store = makeComposerStore(
            recorder: recorder,
            conditions: conditions,
            registryClient: makeOperatorContractRegistryClient(),
        )

        await store.send(.setOperator(propertyKey: "size", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Is between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeNumber"
            $0.conditions[0].valueType = "number"
            $0.conditions[0].values = nil
        }

        await store.send(.setValue(propertyKey: "size", values: ["10", "20"])) {
            $0.conditions[0].values = ["10", "20"]
        }

        await store.send(.setOperator(propertyKey: "size", operatorCode: "eq")) {
            $0.conditions[0].operatorCode = "eq"
            $0.conditions[0].operatorLabel = "Is"
            $0.conditions[0].operatorValueArity = 1
            $0.conditions[0].operatorValueUIKind = "singleNumber"
            $0.conditions[0].valueType = "number"
            $0.conditions[0].values = nil
        }

        await store.send(.setOperator(propertyKey: "size", operatorCode: "exists")) {
            $0.isLoadingFilters = true
            $0.isFilteringInFlight = true
            $0.conditions[0].operatorCode = "exists"
            $0.conditions[0].operatorLabel = "Exists"
            $0.conditions[0].operatorValueArity = 0
            $0.conditions[0].operatorValueUIKind = "none"
            $0.conditions[0].valueType = "string"
            $0.conditions[0].values = []
        }
        await store.receive(\.internal.filtersResponse) {
            $0.isLoadingFilters = false
            $0.isFilteringInFlight = false
            $0.lastFiltersResponse = kEmptySearchResponse
        }

        XCTAssertEqual(store.state.conditions[0].values, [])
        XCTAssertEqual(store.state.conditions[0].operatorCode, "exists")
        XCTAssertEqual(store.state.conditions[0].operatorValueArity, 0)
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
    "size": "File size",
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

private let kRegistryNumberEqOperatorDefinition = OperatorDefinition(
    uiLabel: "Is",
    mdqueryOperator: "==",
    valueShape: .single,
    valueCount: .fixed(1),
    allowedTypes: ["number"],
    inverseOf: nil,
    aliases: nil,
    uiValueKind: ["number": "singleNumber"],
)

private let kRegistryNumberBetweenOperatorDefinition = OperatorDefinition(
    uiLabel: "Is between",
    mdqueryOperator: "RANGE",
    valueShape: .range,
    valueCount: .fixed(2),
    allowedTypes: ["number"],
    inverseOf: nil,
    aliases: nil,
    uiValueKind: ["number": "rangeNumber"],
)

private let kRegistryExistsOperatorDefinition = OperatorDefinition(
    uiLabel: "Exists",
    mdqueryOperator: "EXISTS",
    valueShape: .none,
    valueCount: .fixed(0),
    allowedTypes: ["number"],
    inverseOf: nil,
    aliases: nil,
    uiValueKind: ["number": "none"],
)

private func makeRegistryClient() -> RegistryClient {
    RegistryClient(
        allProperties: { [] },
        labelForKey: { kRegistryLabels[$0] ?? $0 },
        propertyTypeString: registryPropertyType,
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["eq"] },
        operatorDefinition: { _ in kRegistryOperatorDefinition },
        operatorValueUIKind: { _, typeKey in registryUIKind(for: typeKey) },
        resolvePropertyKey: registryResolution,
    )
}

private func makeRangeDateRegistryClient() -> RegistryClient {
    RegistryClient(
        allProperties: { [] },
        labelForKey: { _ in "Modified Date" },
        propertyTypeString: { _ in "date" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["btw"] },
        operatorDefinition: { _ in
            .init(
                uiLabel: "Between",
                mdqueryOperator: "RANGE",
                valueShape: .range,
                valueCount: .fixed(2),
                allowedTypes: ["date"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["date": "rangeDate"],
            )
        },
        operatorValueUIKind: { _, _ in "rangeDate" },
        resolvePropertyKey: { .canonical($0) },
    )
}

private func makeOperatorContractRegistryClient() -> RegistryClient {
    RegistryClient(
        allProperties: { [] },
        labelForKey: { key in
            switch key {
            case "size":
                "File size"
            default:
                key
            }
        },
        propertyTypeString: { _ in "number" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["eq", "btw", "exists"] },
        operatorDefinition: { code in
            switch code {
            case "eq":
                kRegistryNumberEqOperatorDefinition
            case "btw":
                kRegistryNumberBetweenOperatorDefinition
            case "exists":
                kRegistryExistsOperatorDefinition
            default:
                kRegistryNumberEqOperatorDefinition
            }
        },
        operatorValueUIKind: { code, _ in
            switch code {
            case "eq":
                "singleNumber"
            case "btw":
                "rangeNumber"
            case "exists":
                "none"
            default:
                "singleNumber"
            }
        },
        resolvePropertyKey: { .canonical($0) },
    )
}

private func registryPropertyType(for key: String) -> String {
    switch key {
    case "size":
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
        .canonical(key)
    case "file_allocated_size":
        .legacy(original: key, normalized: "size")
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

private func makeNumberCondition(values: [String]?) -> Condition {
    Condition(
        propertyKey: "size",
        propertyLabel: "File size",
        propertyType: "number",
        operatorCode: "eq",
        operatorLabel: "Is",
        operatorValueArity: 1,
        operatorValueUIKind: "singleNumber",
        valueType: "number",
        values: values,
        isActive: true,
    )
}

@MainActor
private func makeComposerStore(
    recorder: FiltersRecorder,
    conditions: [Condition],
    registryClient: RegistryClient = makeRegistryClient(),
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
        $0.registryClient = registryClient
    }

    store.exhaustivity = .off
    return store
}

@MainActor
private func runApplyFiltersTest(
    store: TestStore<ComposerFeature.State, ComposerFeature.Action>,
) async {
    await store.send(.applyFilters)
    await store.receive(\.internal.filtersResponse)
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

private let kEmptySearchResponse = VoyagerShared.SearchResponsePayload(
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
    private var payloads: [VoyagerShared.SearchFiltersPayload] = []

    func append(_ payload: VoyagerShared.SearchFiltersPayload) {
        payloads.append(payload)
    }

    func last() -> VoyagerShared.SearchFiltersPayload? {
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

// swiftlint:enable file_length

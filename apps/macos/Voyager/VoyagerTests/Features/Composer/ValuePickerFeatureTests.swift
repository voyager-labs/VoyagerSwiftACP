import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class ValuePickerFeatureTests: XCTestCase {
    func testPrepareForTagNamesLoadsDeduplicatedFinderTags() async {
        let store = makeStore(
            favoriteTags: [
                Tag(name: "Work", colorCode: 6),
                Tag(name: "work", colorCode: 2),
                Tag(name: "Personal", colorCode: 7),
            ],
        )

        await store.send(
            .prepare(
                .init(
                    propertyKey: "tag_names",
                    operatorCode: "eq",
                    valueType: "string_list",
                    valueUIKind: "listText",
                    valueArity: 1,
                    existingValues: nil,
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "tag_names"
            $0.operatorCode = "eq"
            $0.valueType = "string_list"
            $0.valueUIKind = "listText"
            $0.valueArity = 1
            $0.isCategoricalProperty = true
            $0.values = [""]
            $0.finderTagListState = .init(
                options: [
                    Tag(name: "Work", colorCode: 6),
                    Tag(name: "Personal", colorCode: 7),
                ],
            )
            $0.isPresented = true
        }
    }

    func testAppendTokenDeduplicatesCaseInsensitively() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "tag_names",
                    operatorCode: "eq",
                    valueType: "string_list",
                    valueUIKind: "listText",
                    valueArity: 1,
                    existingValues: ["Work"],
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "tag_names"
            $0.operatorCode = "eq"
            $0.valueType = "string_list"
            $0.valueUIKind = "listText"
            $0.valueArity = 1
            $0.isCategoricalProperty = true
            $0.values = ["Work"]
            $0.finderTagListState = .init(options: [])
            $0.isPresented = true
        }

        await store.send(.appendToken("work"))

        XCTAssertEqual(store.state.values, ["Work"])

        await store.send(.appendToken(" Personal ")) {
            $0.values = ["Work", "Personal"]
        }

        XCTAssertEqual(store.state.values, ["Work", "Personal"])
    }

    func testDeduplicatedTokenValuesTrimsAndDeduplicates() {
        let values = ValueNormalizerUtils.deduplicatedTokenValues([
            " Work ",
            "work",
            "Personal",
            "",
            "  personal  ",
        ])

        XCTAssertEqual(values, ["Work", "Personal"])
    }

    func testCommitRangeNumberClampsExtraInputsToExpectedArity() async {
        let store = TestStore(
            initialState: ValuePickerState(
                isPresented: true,
                propertyKey: "file_allocated_size",
                operatorCode: "btw",
                valueType: "number",
                valueUIKind: "rangeNumber",
                valueArity: 2,
                values: ["10", "20", "30"],
                errorMessage: nil,
                editingIndex: nil,
            ),
        ) {
            ValuePickerFeature()
        }

        await store.send(.commit)
        await store.receive(\.commitResult)
    }

    func testCommitRangeDateDoesNotCommitOnPartialInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["2026-02-26", ""],
                    editingIndex: 0,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["2026-02-26", ""]
            $0.errorMessage = nil
            $0.editingIndex = 0
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeDateDoesNotCommitOnToOnlyInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["", "2026-02-27"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["", "2026-02-27"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeNumberShowsErrorAndResetsInvalidIndex() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "file_allocated_size",
                    operatorCode: "btw",
                    valueType: "number",
                    valueUIKind: "rangeNumber",
                    valueArity: 2,
                    existingValues: ["10", "xx"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "file_allocated_size"
            $0.operatorCode = "btw"
            $0.valueType = "number"
            $0.valueUIKind = "rangeNumber"
            $0.valueArity = 2
            $0.values = ["10", "xx"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit) {
            $0.errorMessage = "Enter valid numbers."
            $0.values = ["10", ""]
        }
    }

    func testCommitRangeNumberDoesNotCommitOnToOnlyInput() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "file_allocated_size",
                    operatorCode: "btw",
                    valueType: "number",
                    valueUIKind: "rangeNumber",
                    valueArity: 2,
                    existingValues: ["", "20"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "file_allocated_size"
            $0.operatorCode = "btw"
            $0.valueType = "number"
            $0.valueUIKind = "rangeNumber"
            $0.valueArity = 2
            $0.values = ["", "20"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit)
    }

    func testCommitRangeDateShowsErrorAndResetsInvalidIndex() async {
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "content_modified_at",
                    operatorCode: "btw",
                    valueType: "date",
                    valueUIKind: "rangeDate",
                    valueArity: 2,
                    existingValues: ["2026-02-26", "invalid-date"],
                    editingIndex: 1,
                ),
            ),
        ) {
            $0.propertyKey = "content_modified_at"
            $0.operatorCode = "btw"
            $0.valueType = "date"
            $0.valueUIKind = "rangeDate"
            $0.valueArity = 2
            $0.values = ["2026-02-26", "invalid-date"]
            $0.errorMessage = nil
            $0.editingIndex = 1
            $0.isPresented = true
        }

        await store.send(.commit) {
            $0.errorMessage = "Enter valid dates."
            $0.values = ["2026-02-26", ""]
        }
    }
}

@MainActor
private func makeStore(
    favoriteTags: [Tag] = [],
) -> TestStore<ValuePickerFeature.State, ValuePickerFeature.Action> {
    let store = TestStore(initialState: ValuePickerFeature.State()) {
        ValuePickerFeature()
    } withDependencies: {
        var registryClient = RegistryClient.testValue
        registryClient.propertyTypeString = { key in
            key == "tag_names" ? "categorical" : "string"
        }
        $0.registryClient = registryClient
        $0.finderFavoritesTagClient = FinderFavoritesTagClient(
            favoriteTagNames: { [] },
            favoriteTags: { favoriteTags },
        )
    }
    store.exhaustivity = .off
    return store
}

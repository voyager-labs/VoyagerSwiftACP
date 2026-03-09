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

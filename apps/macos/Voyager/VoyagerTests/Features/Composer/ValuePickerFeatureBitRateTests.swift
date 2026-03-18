import ComposableArchitecture
import XCTest

@MainActor
final class ValuePickerFeatureBitRateTests: XCTestCase {
    func testPrepareForAudioBitRateUsesPreferredUnitAndConvertedDisplayValue() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "audio_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: ["320000"],
                    existingDisplayValues: nil,
                    preferredUnitCode: "Kbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "audio_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = ["320"]
            $0.unitValueState = .init(
                selectedUnitCode: "Kbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }
    }

    func testCommitForAudioBitRateConvertsDisplayValueToCanonicalBps() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "audio_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: nil,
                    existingDisplayValues: nil,
                    preferredUnitCode: "Kbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "audio_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = [""]
            $0.unitValueState = .init(
                selectedUnitCode: "Kbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }

        await store.send(.setValue(index: 0, text: "320")) {
            $0.values = ["320"]
        }

        await store.send(.commit)
        await store.receive(\.commitResult)
    }

    func testPrepareForVideoBitRateUsesPreferredUnitAndConvertedDisplayValue() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "video_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: ["8000000"],
                    existingDisplayValues: nil,
                    preferredUnitCode: "Mbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "video_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = ["8"]
            $0.unitValueState = .init(
                selectedUnitCode: "Mbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }
    }

    func testCommitForVideoBitRateConvertsDisplayValueToCanonicalBps() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "video_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: nil,
                    existingDisplayValues: nil,
                    preferredUnitCode: "Mbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "video_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = [""]
            $0.unitValueState = .init(
                selectedUnitCode: "Mbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }

        await store.send(.setValue(index: 0, text: "8")) {
            $0.values = ["8"]
        }

        await store.send(.commit)
        await store.receive(\.commitResult)
    }

    func testPrepareForTotalBitRateUsesPreferredUnitAndConvertedDisplayValue() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "total_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: ["1411000"],
                    existingDisplayValues: nil,
                    preferredUnitCode: "Mbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "total_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = ["1.411"]
            $0.unitValueState = .init(
                selectedUnitCode: "Mbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }
    }

    func testCommitForTotalBitRateConvertsDisplayValueToCanonicalBps() async {
        let store = makeStore()

        await store.send(
            .prepare(
                .init(
                    propertyKey: "total_bit_rate",
                    operatorCode: "eq",
                    valueType: "number",
                    valueUIKind: "number",
                    valueArity: 1,
                    existingValues: nil,
                    existingDisplayValues: nil,
                    preferredUnitCode: "Mbps",
                    editingIndex: nil,
                ),
            ),
        ) {
            $0.propertyKey = "total_bit_rate"
            $0.operatorCode = "eq"
            $0.valueType = "number"
            $0.valueUIKind = "number"
            $0.valueArity = 1
            $0.values = [""]
            $0.unitValueState = .init(
                selectedUnitCode: "Mbps",
                availableUnitCodes: ["bps", "Kbps", "Mbps"],
                unitLabelsByCode: ["bps": "bps", "Kbps": "Kbps", "Mbps": "Mbps"],
            )
            $0.finderTagListState = nil
            $0.isPresented = true
        }

        await store.send(.setValue(index: 0, text: "1.411")) {
            $0.values = ["1.411"]
        }

        await store.send(.commit)
        await store.receive(\.commitResult)
    }
}

@MainActor
private func makeStore(
    favoriteTags: [Tag] = [],
) -> TestStore<ValuePickerFeature.State, ValuePickerFeature.Action> {
    let store = TestStore(initialState: ValuePickerFeature.State()) {
        ValuePickerFeature()
    } withDependencies: {
        var registryClient = RegistryTestSupport.makeRegistryClient()
        registryClient.propertyTypeString = { key in
            key == "tag_names" ? "categorical" : RegistryTestSupport.propertyTypeString(for: key)
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

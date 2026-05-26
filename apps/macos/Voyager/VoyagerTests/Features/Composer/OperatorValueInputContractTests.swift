import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

/// 연산자 값 입력 계약 — 연산자 전환 시 인자 수 업데이트와 페이로드 리셋을 검증.
@MainActor
final class OperatorValueInputContractTests: XCTestCase {
    /// testSetOperatorExistsConfiguresNoValueInput 테스트 동작을 검증한다.
    func testSetOperatorExistsConfiguresNoValueInput() async {
        let store = TestStore(initialState: makeState()) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        store.exhaustivity = .off

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "exists")) {
            $0.conditions[0].operatorCode = "exists"
            $0.conditions[0].operatorLabel = "Exists"
            $0.conditions[0].operatorValueArity = 0
            $0.conditions[0].operatorValueUIKind = "none"
            $0.conditions[0].valueType = "string"
            $0.conditions[0].values = []
            $0.history = [
                FilterSnapshot(
                    scopes: ["/tmp"],
                    conditions: [
                        .init(
                            propertyKey: "name_stem",
                            propertyLabel: "Name",
                            propertyType: "date",
                            operatorCode: nil,
                            operatorLabel: nil,
                            operatorValueArity: nil,
                            operatorValueUIKind: nil,
                            valueType: "date",
                            values: nil,
                        ),
                    ],
                    conditionDisplayByKey: [:],
                ),
            ]
        }
    }

    /// testSetOperatorBetweenConfiguresRangeDateInputs 테스트 동작을 검증한다.
    func testSetOperatorBetweenConfiguresRangeDateInputs() async {
        let store = TestStore(initialState: makeState()) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeDate"
            $0.conditions[0].valueType = "date"
            $0.conditions[0].values = nil
            $0.history = [
                FilterSnapshot(
                    scopes: ["/tmp"],
                    conditions: [
                        .init(
                            propertyKey: "name_stem",
                            propertyLabel: "Name",
                            propertyType: "date",
                            operatorCode: nil,
                            operatorLabel: nil,
                            operatorValueArity: nil,
                            operatorValueUIKind: nil,
                            valueType: "date",
                            values: nil,
                        ),
                    ],
                    conditionDisplayByKey: [:],
                ),
            ]
        }
    }

    /// testSetOperatorResetsValuePickerPayloadForSameProperty 테스트 동작을 검증한다.
    func testSetOperatorResetsValuePickerPayloadForSameProperty() async {
        var initial = makeState()
        initial.valuePicker = .init()
        initial.valuePicker.propertyKey = "name_stem"
        initial.valuePicker.operatorCode = "eq"
        initial.valuePicker.isPresented = true
        initial.valuePicker.valueType = "string"
        initial.valuePicker.valueUIKind = "singleText"
        initial.valuePicker.valueArity = 1
        initial.valuePicker.values = ["report"]
        initial.valuePicker.errorMessage = "x"

        let store = TestStore(initialState: initial) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeDate"
            $0.conditions[0].valueType = "date"
            $0.conditions[0].values = nil

            $0.valuePicker.isPresented = false
            $0.valuePicker.propertyKey = nil
            $0.valuePicker.operatorCode = nil
            $0.valuePicker.valueUIKind = "singleText"
            $0.valuePicker.valueType = "string"
            $0.valuePicker.values = ["", ""]
            $0.valuePicker.errorMessage = nil
            $0.history = [
                FilterSnapshot(
                    scopes: ["/tmp"],
                    conditions: [
                        .init(
                            propertyKey: "name_stem",
                            propertyLabel: "Name",
                            propertyType: "date",
                            operatorCode: nil,
                            operatorLabel: nil,
                            operatorValueArity: nil,
                            operatorValueUIKind: nil,
                            valueType: "date",
                            values: nil,
                        ),
                    ],
                    conditionDisplayByKey: [:],
                ),
            ]
        }
    }

    private func makeState() -> ComposerState {
        var state = ComposerState()
        state.scopes = ["/tmp"]
        state.conditions = [
            .init(
                propertyKey: "name_stem",
                propertyLabel: "Name",
                propertyType: "date",
                operatorCode: nil,
                operatorLabel: nil,
                operatorValueArity: nil,
                operatorValueUIKind: nil,
                valueType: "date",
                values: nil,
            ),
        ]
        return state
    }

    private func makeRegistryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Name" },
            propertyTypeString: { _ in "date" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["exists", "btw"] },
            operatorDefinition: { code in
                switch code {
                case "exists":
                    .init(
                        uiLabel: "Exists",
                        mdqueryOperator: nil,
                        valueShape: ValueShape.none,
                        valueCount: .fixed(0),
                        allowedTypes: ["date"],
                        inverseOf: nil,
                        aliases: nil,
                        uiValueKind: ["date": "none"],
                    )
                case "btw":
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
                default:
                    .init(
                        uiLabel: code,
                        mdqueryOperator: nil,
                        valueShape: .single,
                        valueCount: .fixed(1),
                        allowedTypes: nil,
                        inverseOf: nil,
                        aliases: nil,
                        uiValueKind: ["date": "singleText"],
                    )
                }
            },
            operatorValueUIKind: { code, _ in
                code == "exists" ? "none" : "rangeDate"
            },
            resolvePropertyKey: { .canonical($0) },
        )
    }
}

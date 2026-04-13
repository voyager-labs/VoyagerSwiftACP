import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class OperatorValueInputContractTests: XCTestCase {
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
        }
    }

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
        }
    }

    func testSetOperatorResetsValuePickerPayloadForSameProperty() async {
        var initial = makeState()
        initial.valuePicker = .init(
            propertyKey: "name_stem",
            operatorCode: "eq",
            isPresented: true,
            valueType: "string",
            valueUIKind: "singleText",
            valueArity: 1,
            values: ["report"],
            errorMessage: "x",
        )

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
        }
    }

    private func makeState() -> ComposerState {
        .init(
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
        )
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
                        valueShape: .none,
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

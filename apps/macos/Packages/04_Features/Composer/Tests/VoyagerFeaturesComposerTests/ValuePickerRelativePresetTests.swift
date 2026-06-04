import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class ValuePickerRelativePresetTests: XCTestCase {
    func testRelativePresetSelectionPersistsUntilCustomInput() async {
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )

        let store = TestStore(initialState: initialState) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let sevenDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDatePreset(.daysAgo7)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativePreset = .daysAgo7
            $0.dateValueState?.relativeDirection = .past
            $0.dateValueState?.relativeAmount = 7
            $0.dateValueState?.relativeUnit = .day
            $0.dateValueState?.selectedDate = sevenDaysAgo
        }

        let nineDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -9, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDateAmount(9)) {
            $0.dateValueState?.relativePreset = .custom
            $0.dateValueState?.relativeAmount = 9
            $0.dateValueState?.selectedDate = nineDaysAgo
        }
    }

    private func makeRegistryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Modified" },
            propertyTypeString: { _ in "date" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { code in
                .init(
                    uiLabel: code,
                    mdqueryOperator: nil,
                    valueShape: .single,
                    valueCount: .fixed(1),
                    allowedTypes: ["date"],
                    inverseOf: nil,
                    aliases: nil,
                    uiValueKind: ["date": "singleDate"],
                )
            },
            operatorValueUIKind: { _, _ in "singleDate" },
            resolvePropertyKey: { .canonical($0) },
        )
    }
}

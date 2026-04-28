import ComposableArchitecture
import SwiftUI

import VoyagerEntitiesEntry

struct ConditionChipValueSectionView: View {
    let condition: Condition
    let displayState: ConditionDisplayState?
    let isDark: Bool
    let hoverFillOpacity: Double
    let valuePickerStore: StoreOf<ValuePickerFeature>
    let onDisplayUnitChange: (_ propertyKey: String, _ unitCode: String) -> Void

    @State var isValueHovering = false
    @State var datePopoverIndex: Int?
    @State var tempDate: Date = .init()
    @State var dateHoverIndex: Int?
    @State var boolPopoverIndex: Int?
    @State var boolHoverIndex: Int?
    @State var boolOptionHoverValue: String?
    @FocusState var focusedValueIndex: Int?

    var displayUnitValueState: UnitValueState? {
        displayState?.unitValueState
    }

    let rangeSep = "-"

    var body: some View {
        WithViewStore(valuePickerStore, observe: { $0 }, content: { valueStore in
            valueSection(valueStore: valueStore)
        })
    }

    @ViewBuilder
    func valueSection(
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        let valueUIKind = condition.operatorValueUIKind ?? "singleText"
        let valueArity = condition.operatorValueArity ?? ValueNormalizerUtils.expectedArity(for: valueUIKind)
        let isDateType = condition.valueType == "date" || condition.valueType == "datetime"
        let isEditingValue = !isDateType && condition.valueType != "boolean" && valueStore.isPresented &&
            valueStore.propertyKey == condition.propertyKey

        if let operatorCode = condition.operatorCode, valueArity != 0 {
            if valueUIKind == "rangeNumber" {
                rangeNumberSection(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                    valueStore: valueStore,
                )
            } else if isDateType {
                dateValueSection(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                    valueViewStore: valueStore,
                )
            } else {
                nonDateValueSection(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                    isEditingValue: isEditingValue,
                    valueStore: valueStore,
                )
            }
        }
    }

    func currentUnitValueState(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
    ) -> UnitValueState? {
        if let valueViewStore,
           valueViewStore.propertyKey == condition.propertyKey,
           let unitValueState = valueViewStore.unitValueState
        {
            return unitValueState
        }
        return displayUnitValueState
    }

    func currentDisplayValues(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
    ) -> [String]? {
        if let valueViewStore, valueViewStore.propertyKey == condition.propertyKey {
            return valueViewStore.values
        }
        return displayState?.values ?? condition.values
    }

    func makePreparePayload(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        editingIndex: Int?,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
        existingValues: [String]? = nil,
        includeDisplayState: Bool = true,
        valueType: String? = nil,
    ) -> PreparePayload {
        PreparePayload(
            propertyKey: condition.propertyKey,
            operatorCode: operatorCode,
            valueType: valueType ?? condition.valueType,
            valueUIKind: valueUIKind,
            valueArity: valueArity,
            existingValues: existingValues ?? condition.values,
            existingDisplayValues: includeDisplayState ? currentDisplayValues(valueViewStore: valueStore) : nil,
            preferredUnitCode: includeDisplayState ? currentUnitValueState(valueViewStore: valueStore)?
                .selectedUnitCode : nil,
            editingIndex: editingIndex,
        )
    }

    func sendPrepare(
        operatorCode: String,
        valueUIKind: String,
        valueArity: Int,
        editingIndex: Int?,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
        existingValues: [String]? = nil,
        includeDisplayState: Bool = true,
        valueType: String? = nil,
    ) {
        valuePickerStore.send(
            .prepare(
                makePreparePayload(
                    operatorCode: operatorCode,
                    valueUIKind: valueUIKind,
                    valueArity: valueArity,
                    editingIndex: editingIndex,
                    valueStore: valueStore,
                    existingValues: existingValues,
                    includeDisplayState: includeDisplayState,
                    valueType: valueType,
                ),
            ),
        )
    }
}

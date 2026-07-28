import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection

struct ConditionChipValueSectionView: View {
    let store: StoreOf<ConditionEditorFeature>
    let condition: Condition
    let displayState: ConditionDisplayState?
    let isDark: Bool
    let hoverFillOpacity: Double

    @State var isValueHovering = false
    @State var datePopoverIndex: Int?
    @State var tempDate: Date = .init()
    @State var dateHoverIndex: Int?
    @FocusState var focusedValueIndex: Int?

    let rangeSep = "-"

    var valuePickerStore: StoreOf<ValuePickerFeature> {
        store.scope(state: \.valuePicker, action: \.valuePicker)
    }

    var body: some View {
        WithViewStore(
            valuePickerStore,
            observe: { $0 },
            content: { valueStore in valueSection(valueStore: valueStore) },
        )
    }

    @ViewBuilder
    private func valueSection(
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>,
    ) -> some View {
        if let contract = condition.operation?.valueContract {
            switch contract.input {
            case .none:
                EmptyView()
            case .singleDate, .rangeDate:
                dateValueSection(contract: contract, valueViewStore: valueStore)
            case .rangeNumber:
                rangeNumberSection(contract: contract, valueStore: valueStore)
            case .toggle:
                booleanValueButton(
                    placeholderText: "",
                    currentText: condition.values?.first ?? "",
                    index: 0,
                    valueViewStore: valueStore,
                    contract: contract,
                )
            case .listText where condition.property.type.rawValue == "categorical":
                tokenValueButton(contract: contract, valueViewStore: valueStore)
            case .singleText, .listText, .singleNumber, .listNumber:
                ordinaryValueSection(contract: contract, valueStore: valueStore)
            }
        }
    }

    func currentUnitValueState(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
    ) -> UnitValueState? {
        valueViewStore?.unitValueState ?? displayState?.unitValueState
    }

    func currentDisplayValues(
        valueViewStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
    ) -> [String]? {
        valueViewStore?.isPresented == true ? valueViewStore?.values : displayState?.values ?? condition.values
    }

    func prepare(
        editingIndex: Int?,
        valueStore: ViewStore<ValuePickerFeature.State, ValuePickerFeature.Action>? = nil,
        existingValues: [String]? = nil,
        includeDisplayState: Bool = true,
    ) {
        valuePickerStore.send(.prepare(.init(
            condition: condition,
            existingDisplayValues: includeDisplayState ? currentDisplayValues(valueViewStore: valueStore) :
                existingValues,
            preferredUnitCode: includeDisplayState ? currentUnitValueState(valueViewStore: valueStore)?
                .selectedUnitCode : nil,
            editingIndex: editingIndex,
        )))
    }
}

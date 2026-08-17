import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

@Reducer
public struct ConditionEditorFeature {
    public typealias State = ConditionEditorState
    public typealias Action = ConditionEditorAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.propertyPicker, action: \.propertyPicker) {
            ConditionPropertyPickerFeature()
        }
        Scope(state: \.valuePicker, action: \.valuePicker) {
            ValuePickerFeature()
        }
        Reduce { state, action in
            switch action {
            case let .view(.setPropertyPickerPresented(isPresented)):
                state.propertyPicker.isPresented = isPresented
                if !isPresented {
                    state.propertyQuery = ""
                    state.propertyPicker.searchText = ""
                }
                return .none

            case let .view(.setPropertyQuery(query)):
                state.propertyQuery = query
                state.propertyPicker.searchText = query
                return .none

            case let .view(.selectProperty(key)):
                state.resetTransientState()
                return .send(.delegate(.replaceProperty(key)))

            case let .view(.setOperatorMenuPresented(isPresented)):
                state.isOperatorMenuPresented = isPresented
                return .none

            case let .view(.selectOperator(code)):
                guard state.condition.property.operatorOptions.contains(where: { $0.code == code }) else {
                    return .none
                }
                state.resetTransientState()
                return .send(.delegate(.selectOperator(code)))

            case let .view(.setValuePickerPresented(isPresented)):
                state.isValuePickerPresented = isPresented
                if !isPresented {
                    state.draftValues = state.displayState?.values ?? state.condition.values ?? []
                    state.editingIndex = nil
                    state.errorMessage = nil
                }
                return .none

            case let .view(.setDraftValue(index, text)):
                guard index >= 0 else { return .none }
                if state.draftValues.count <= index {
                    state.draftValues.append(contentsOf: repeatElement("", count: index - state.draftValues.count + 1))
                }
                state.draftValues[index] = text
                state.errorMessage = nil
                return .none

            case let .view(.setEditingIndex(index)):
                state.editingIndex = index
                return .none

            case .view(.commitValues):
                guard let contract = state.valueContract else { return .none }
                let result = ConditionValueNormalizer.normalize(
                    contract: contract,
                    rawValues: state.draftValues,
                    editingIndex: state.editingIndex,
                )
                guard let values = result.values else {
                    state.errorMessage = result.errorMessage
                    for index in result.resetIndices where state.draftValues.indices.contains(index) {
                        state.draftValues[index] = ""
                    }
                    return .none
                }
                state.errorMessage = nil
                state.isValuePickerPresented = false
                return .send(.delegate(.commitValues(
                    values: values,
                    displayValues: state.draftValues,
                    selectedUnitCode: state.displayState?.unitValueState?.selectedUnitCode,
                )))

            case let .view(.setDisplayUnit(unitCode)):
                guard let contract = state.condition.property.unitContract,
                      ConditionUnitConverter.unitCodes(contract: contract).contains(unitCode)
                else {
                    return .none
                }
                return .send(.delegate(.setDisplayUnit(unitCode)))

            case .view(.dismiss):
                state.resetTransientState()
                return .none

            case let .propertyPicker(.propertyTapped(key)):
                state.resetTransientState()
                return .send(.delegate(.replaceProperty(key)))

            case let .valuePicker(.commitResult(values, displayValues, selectedUnitCode)):
                state.errorMessage = nil
                state.isValuePickerPresented = false
                return .send(.delegate(.commitValues(
                    values: values,
                    displayValues: displayValues,
                    selectedUnitCode: selectedUnitCode,
                )))

            case .propertyPicker, .valuePicker, .delegate:
                return .none
            }
        }
    }
}

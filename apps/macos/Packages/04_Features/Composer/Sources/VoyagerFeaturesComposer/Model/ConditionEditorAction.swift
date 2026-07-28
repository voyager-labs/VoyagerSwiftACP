import ComposableArchitecture
import Foundation

@CasePathable
public enum ConditionEditorAction: CasePathable, Sendable {
    case propertyPicker(ConditionPropertyPickerAction)
    case valuePicker(ValuePickerAction)
    case view(View)
    case delegate(Delegate)

    @CasePathable
    public enum View: Sendable {
        case setPropertyPickerPresented(Bool)
        case setPropertyQuery(String)
        case selectProperty(String)
        case setOperatorMenuPresented(Bool)
        case selectOperator(String)
        case setValuePickerPresented(Bool)
        case setDraftValue(index: Int, text: String)
        case setEditingIndex(Int?)
        case commitValues
        case setDisplayUnit(String)
        case dismiss
    }

    @CasePathable
    public enum Delegate: Sendable {
        case replaceProperty(String)
        case selectOperator(String)
        case commitValues(values: [String], displayValues: [String], selectedUnitCode: String?)
        case setDisplayUnit(String)
    }
}

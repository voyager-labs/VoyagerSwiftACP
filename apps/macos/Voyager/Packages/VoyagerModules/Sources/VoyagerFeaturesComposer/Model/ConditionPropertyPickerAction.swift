import ComposableArchitecture

@CasePathable
public enum ConditionPropertyPickerAction: CasePathable, Sendable {
    case setPresented(Bool)
    case onAppear
    case searchTextChanged(String)
    case categoryTapped(String)
    case backFromCategory
    case propertyTapped(String)
    case startEditing(String)
    case clearDuplicateMessage
}

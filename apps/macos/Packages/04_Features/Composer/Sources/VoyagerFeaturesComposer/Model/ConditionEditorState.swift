import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

@ObservableState
public struct ConditionEditorState: Equatable, Identifiable {
    public let id: UUID
    public let condition: Condition
    public var displayState: ConditionDisplayState?
    public var propertyPicker: ConditionPropertyPickerState = .init()
    public var valuePicker: ValuePickerState = .init()
    public var isOperatorMenuPresented = false
    public var isValuePickerPresented = false
    public var propertyQuery = ""
    public var draftValues: [String]
    public var editingIndex: Int?
    public var errorMessage: String?

    public init(id: UUID, condition: Condition, displayState: ConditionDisplayState? = nil) {
        self.id = id
        self.condition = condition
        self.displayState = displayState
        draftValues = displayState?.values ?? condition.values ?? []
    }

    public var valueContract: Condition.ValueContract? {
        condition.operation?.valueContract
    }

    public mutating func resetTransientState() {
        propertyPicker = .init()
        valuePicker = .init()
        isOperatorMenuPresented = false
        isValuePickerPresented = false
        propertyQuery = ""
        draftValues = displayState?.values ?? condition.values ?? []
        editingIndex = nil
        errorMessage = nil
    }
}

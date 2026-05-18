import ComposableArchitecture
import Foundation

@CasePathable
public enum ValuePickerAction: CasePathable, Sendable {
    case setPresented(Bool)
    case prepare(PreparePayload)

    case setValue(index: Int, text: String)
    case selectUnit(String)
    case setTokenInput(String)
    case appendToken(String)
    case removeToken(String)
    case commit
    case commitResult(
        propertyKey: String,
        values: [String],
        displayValues: [String],
        selectedUnitCode: String?
    )
}

public struct PreparePayload: Sendable, Equatable {
    public let propertyKey: String
    public let operatorCode: String
    public let valueType: String
    public let valueUIKind: String
    public let valueArity: Int
    public let existingValues: [String]?
    public let existingDisplayValues: [String]?
    public let preferredUnitCode: String?
    public let editingIndex: Int?

    public init(
        propertyKey: String,
        operatorCode: String,
        valueType: String,
        valueUIKind: String,
        valueArity: Int,
        existingValues: [String]?,
        existingDisplayValues: [String]?,
        preferredUnitCode: String?,
        editingIndex: Int?
    ) {
        self.propertyKey = propertyKey
        self.operatorCode = operatorCode
        self.valueType = valueType
        self.valueUIKind = valueUIKind
        self.valueArity = valueArity
        self.existingValues = existingValues
        self.existingDisplayValues = existingDisplayValues
        self.preferredUnitCode = preferredUnitCode
        self.editingIndex = editingIndex
    }
}

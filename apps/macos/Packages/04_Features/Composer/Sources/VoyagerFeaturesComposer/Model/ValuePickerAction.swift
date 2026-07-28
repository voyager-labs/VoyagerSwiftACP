import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

@CasePathable
public enum ValuePickerAction: CasePathable, Sendable, Equatable {
    case setPresented(Bool)
    case prepare(PreparePayload)

    case setValue(index: Int, text: String)
    case setDateMode(DateValueState.Mode)
    case setDateSelection(Date)
    case setRelativeDateDirection(RelativeDateConditionLiteral.Direction)
    case setRelativeDateAmount(Int)
    case setRelativeDateUnit(RelativeDateConditionLiteral.Unit)
    case setRelativeDatePreset(DateValueState.RelativePreset)
    case selectUnit(String)
    case setTokenInput(String)
    case appendToken(String)
    case removeToken(String)
    case commit
    case commitResult(
        values: [String],
        displayValues: [String],
        selectedUnitCode: String?,
    )
}

public struct PreparePayload: Sendable, Equatable {
    public let condition: Condition
    public let existingValues: [String]?
    public let existingDisplayValues: [String]?
    public let preferredUnitCode: String?
    public let editingIndex: Int?

    public init(
        condition: Condition,
        existingDisplayValues: [String]?,
        preferredUnitCode: String?,
        editingIndex: Int?,
    ) {
        self.condition = condition
        existingValues = condition.values
        self.existingDisplayValues = existingDisplayValues
        self.preferredUnitCode = preferredUnitCode
        self.editingIndex = editingIndex
    }
}

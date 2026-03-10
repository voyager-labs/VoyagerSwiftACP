import ComposableArchitecture
import Foundation

@CasePathable
enum ValuePickerAction: CasePathable, Sendable {
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
        selectedUnitCode: String?,
    )
}

struct PreparePayload: Sendable, Equatable {
    let propertyKey: String
    let operatorCode: String
    let valueType: String
    let valueUIKind: String
    let valueArity: Int
    let existingValues: [String]?
    let existingDisplayValues: [String]?
    let preferredUnitCode: String?
    let editingIndex: Int?
}

import ComposableArchitecture
import Foundation

@CasePathable
enum ValuePickerAction: CasePathable, Sendable {
    case setPresented(Bool)
    case prepare(PreparePayload)

    case setValue(index: Int, text: String)
    case setTokenInput(String)
    case appendToken(String)
    case removeToken(String)
    case commit
    case commitResult(propertyKey: String, values: [String])
}

struct PreparePayload: Sendable, Equatable {
    let propertyKey: String
    let operatorCode: String
    let valueType: String
    let valueUIKind: String
    let valueArity: Int
    let existingValues: [String]?
    let editingIndex: Int?
}

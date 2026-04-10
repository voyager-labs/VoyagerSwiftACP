import ComposableArchitecture
import Foundation

@CasePathable
enum OperatorPickerAction: CasePathable, Sendable {
    case setPresented(Bool)
    case prepare(propertyKey: String, options: [String], optionLabels: [String: String])
    case select(String)
}

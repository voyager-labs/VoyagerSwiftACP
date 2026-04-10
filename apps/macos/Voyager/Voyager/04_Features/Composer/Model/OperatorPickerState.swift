import ComposableArchitecture
import Foundation

@ObservableState
struct OperatorPickerState: Equatable {
    var isPresented: Bool = false
    var options: [String] = []
    var optionLabels: [String: String] = [:]
    var propertyKey: String?
}

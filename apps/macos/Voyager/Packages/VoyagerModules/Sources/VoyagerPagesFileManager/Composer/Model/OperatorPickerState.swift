import ComposableArchitecture
import Foundation

@ObservableState
public struct OperatorPickerState: Equatable {
    public var isPresented: Bool = false
    public var options: [String] = []
    public var optionLabels: [String: String] = [:]
    public var propertyKey: String?
}

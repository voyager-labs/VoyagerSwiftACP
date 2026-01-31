import ComposableArchitecture
import Foundation

@ObservableState
struct ValuePickerState: Equatable {
    var isPresented: Bool = false
    var propertyKey: String?
    var operatorCode: String?
    var valueType: String = "string"
    var valueUIKind: String = "singleText"
    var valueArity: Int = 1
    var values: [String] = [""]
    var errorMessage: String?
    var editingIndex: Int?
}

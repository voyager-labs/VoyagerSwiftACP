import ComposableArchitecture
import Foundation

@ObservableState
struct ValuePickerState: Equatable {
    var propertyKey: String?
    var operatorCode: String?
    var isPresented: Bool = false

    var valueType: String = "string"
    var valueUIKind: String = "singleText"
    var valueArity: Int = 1
    var isCategoricalProperty: Bool = false

    var values: [String] = [""]
    var unitValueState: UnitValueState?
    var tokenInput: String = ""
    var finderTagListState: FinderTagListState?
    var errorMessage: String?
    var editingIndex: Int?
}

struct FinderTagListState: Equatable {
    var options: [Tag]
}

struct UnitValueState: Equatable {
    var selectedUnitCode: String
    var availableUnitCodes: [String]
}

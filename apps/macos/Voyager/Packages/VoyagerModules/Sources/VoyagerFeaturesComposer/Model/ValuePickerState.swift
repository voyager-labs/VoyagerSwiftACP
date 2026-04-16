import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry

@ObservableState
public struct ValuePickerState: Equatable {
    public var propertyKey: String?
    public var operatorCode: String?
    public var isPresented: Bool = false

    public var valueType: String = "string"
    public var valueUIKind: String = "singleText"
    public var valueArity: Int = 1
    public var isCategoricalProperty: Bool = false

    public var values: [String] = [""]
    public var unitValueState: UnitValueState?
    public var tokenInput: String = ""
    public var finderTagListState: FinderTagListState?
    public var errorMessage: String?
    public var editingIndex: Int?

    public init() {}
}

public struct FinderTagListState: Equatable {
    public var options: [Tag]

    public init(options: [Tag] = []) {
        self.options = options
    }
}

public struct UnitValueState: Equatable {
    public var selectedUnitCode: String
    public var availableUnitCodes: [String]
    public var unitLabelsByCode: [String: String]

    public init(
        selectedUnitCode: String = "",
        availableUnitCodes: [String] = [],
        unitLabelsByCode: [String: String] = [:],
    ) {
        self.selectedUnitCode = selectedUnitCode
        self.availableUnitCodes = availableUnitCodes
        self.unitLabelsByCode = unitLabelsByCode
    }
}

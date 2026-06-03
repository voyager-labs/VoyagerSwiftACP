import ComposableArchitecture
import Foundation
import VoyagerEntitiesTag
import VoyagerShared

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
    public var dateValueState: DateValueState?

    public init() {}
}

public struct DateValueState: Equatable {
    public enum Mode: String, CaseIterable, Sendable {
        case absolute
        case relative
        case today
    }

    public enum RelativePreset: String, CaseIterable, Sendable {
        case custom
        case today
        case yesterday
        case last7Days
        case last30Days
        case last3Months
        case lastYear
    }

    public var mode: Mode
    public var selectedDate: Date
    public var relativeDirection: RelativeDateConditionLiteral.Direction
    public var relativeAmount: Int
    public var relativeUnit: RelativeDateConditionLiteral.Unit
    public var relativePreset: RelativePreset

    public init(
        mode: Mode,
        selectedDate: Date,
        relativeDirection: RelativeDateConditionLiteral.Direction,
        relativeAmount: Int,
        relativeUnit: RelativeDateConditionLiteral.Unit,
        relativePreset: RelativePreset = .custom,
    ) {
        self.mode = mode
        self.selectedDate = selectedDate
        self.relativeDirection = relativeDirection
        self.relativeAmount = max(1, relativeAmount)
        self.relativeUnit = relativeUnit
        self.relativePreset = relativePreset
    }

    public func displayText() -> String {
        switch mode {
        case .absolute:
            DateNormalizerUtils.formatDateOnly(selectedDate)
        case .relative:
            RelativeDateConditionLiteral.displayText(
                direction: relativeDirection,
                amount: relativeAmount,
                unit: relativeUnit,
                anchorDateLiteral: DateNormalizerUtils.formatDateOnly(Date()),
            )
        case .today:
            "Today"
        }
    }
}

public struct FinderTagListState: Equatable {
    public var options: [Tag]

    public init(options: [Tag]) {
        self.options = options
    }
}

public struct UnitValueState: Equatable {
    public var selectedUnitCode: String
    public var availableUnitCodes: [String]
    public var unitLabelsByCode: [String: String]

    public init(selectedUnitCode: String, availableUnitCodes: [String], unitLabelsByCode: [String: String]) {
        self.selectedUnitCode = selectedUnitCode
        self.availableUnitCodes = availableUnitCodes
        self.unitLabelsByCode = unitLabelsByCode
    }
}

import VoyagerEntitiesCollection

public struct UnitValueState: Equatable {
    public var selectedUnitCode: String
    public var availableUnitCodes: [String]
    public var unitLabelsByCode: [String: String]

    public init(contract: Condition.UnitContract, preferredUnitCode: String? = nil) {
        let codes = ConditionUnitConverter.unitCodes(contract: contract)
        availableUnitCodes = codes
        selectedUnitCode = preferredUnitCode.flatMap { codes.contains($0) ? $0 : nil }
            ?? ConditionUnitConverter.defaultDisplayUnitCode(contract: contract)
        unitLabelsByCode = Dictionary(uniqueKeysWithValues: availableUnitCodes.map {
            ($0, ConditionUnitConverter.unitLabel(for: $0, contract: contract))
        })
    }

    public func label(for code: String) -> String {
        unitLabelsByCode[code] ?? code
    }
}

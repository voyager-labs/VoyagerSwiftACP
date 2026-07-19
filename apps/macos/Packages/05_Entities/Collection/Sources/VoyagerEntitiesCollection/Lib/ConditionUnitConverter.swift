import Foundation

public enum ConditionUnitConverter {
    public static func unitCodes(contract: Condition.UnitContract) -> [String] {
        contract.options.map(\.code)
    }

    public static func unitLabel(for code: String, contract: Condition.UnitContract) -> String {
        contract.options.first(where: { $0.code == code })?.label ?? code
    }

    public static func defaultDisplayUnitCode(contract: Condition.UnitContract) -> String {
        contract.options.first(where: { $0.label == contract.defaultDisplayUnit })?.code ?? contract.canonicalUnit
    }

    public static func toCanonical(displayValueText: String, from unit: String,
                                   contract: Condition.UnitContract) -> String?
    {
        guard let value = decimal(displayValueText),
              let factor = contract.options.first(where: { $0.code == unit })?.factorToCanonical else { return nil }
        return formatted(value * factor)
    }

    public static func fromCanonical(canonicalText: String, to unit: String,
                                     contract: Condition.UnitContract) -> String?
    {
        guard let value = decimal(canonicalText),
              let factor = contract.options.first(where: { $0.code == unit })?.factorToCanonical,
              factor != .zero else { return nil }
        return formatted(value / factor)
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func formatted(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

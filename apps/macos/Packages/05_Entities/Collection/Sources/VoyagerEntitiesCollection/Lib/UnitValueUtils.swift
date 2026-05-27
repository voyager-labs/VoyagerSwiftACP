import Foundation

public enum UnitValueUtils {
    public struct UnitOption: Equatable, Sendable {
        public let code: String
        public let label: String

        public init(code: String, label: String) {
            self.code = code
            self.label = label
        }
    }

    public struct UnitSpec: Equatable, Sendable {
        public let canonicalUnit: String
        public let units: [UnitOption]
        public let defaultDisplayUnit: String
        fileprivate let factorsToCanonical: [String: Decimal]

        public init(
            canonicalUnit: String,
            units: [UnitOption],
            defaultDisplayUnit: String,
            factorsToCanonical: [String: Decimal],
        ) {
            self.canonicalUnit = canonicalUnit
            self.units = units
            self.defaultDisplayUnit = defaultDisplayUnit
            self.factorsToCanonical = factorsToCanonical
        }
    }

    public static func spec(for propertyKey: String, registryClient: RegistryClient) -> UnitSpec? {
        guard let registrySpec = registryClient.unitSpec(for: propertyKey) else {
            return nil
        }

        let factorsToCanonical = Dictionary(uniqueKeysWithValues: registrySpec.units.map { option in
            guard let factor = Decimal(string: option.factorToCanonical, locale: Locale(identifier: "en_US_POSIX"))
            else {
                preconditionFailure(
                    "Invalid unit factor: \(propertyKey) / \(option.code) / \(option.factorToCanonical)",
                )
            }
            return (option.code, factor)
        })

        return UnitSpec(
            canonicalUnit: registrySpec.canonicalUnit,
            units: registrySpec.units.map { .init(code: $0.code, label: $0.label) },
            defaultDisplayUnit: registrySpec.defaultDisplayUnit,
            factorsToCanonical: factorsToCanonical,
        )
    }

    public static func supportsUnits(propertyKey: String, valueType: String, registryClient: RegistryClient) -> Bool {
        valueType == "number" && spec(for: propertyKey, registryClient: registryClient) != nil
    }

    public static func unitCodes(spec: UnitSpec) -> [String] {
        spec.units.map(\.code)
    }

    public static func unitLabel(for code: String, spec: UnitSpec) -> String {
        spec.units.first(where: { $0.code == code })?.label ?? code
    }

    public static func unitCode(for label: String, spec: UnitSpec) -> String? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return spec.units.first(where: { $0.label.lowercased() == normalized })?.code
    }

    public static func defaultDisplayUnitCode(spec: UnitSpec) -> String {
        unitCode(for: spec.defaultDisplayUnit, spec: spec) ?? spec.canonicalUnit
    }

    public static func toCanonical(
        displayValueText: String,
        from unit: String,
        spec: UnitSpec,
    ) -> String? {
        guard let value = parseDecimal(displayValueText),
              let factor = spec.factorsToCanonical[unit]
        else {
            return nil
        }
        return formatDecimal(value * factor)
    }

    public static func fromCanonical(
        canonicalText: String,
        to unit: String,
        spec: UnitSpec,
    ) -> String? {
        guard let value = parseDecimal(canonicalText),
              let factor = spec.factorsToCanonical[unit],
              factor != .zero
        else {
            return nil
        }
        return formatDecimal(value / factor)
    }

    public static func stripUnitSuffixIfNeeded(_ text: String, spec: UnitSpec) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for code in unitCodes(spec: spec) {
            let label = unitLabel(for: code, spec: spec)
            if trimmed.lowercased().hasSuffix(" " + label.lowercased()) {
                return String(trimmed.dropLast(label.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.lowercased().hasSuffix(" " + code.lowercased()) {
                return String(trimmed.dropLast(code.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    public static func strippedDisplayValues(_ values: [String], spec: UnitSpec) -> [String] {
        values.map { stripUnitSuffixIfNeeded($0, spec: spec) }
    }

    public static func toCanonicalValues(
        displayValues: [String],
        from unit: String,
        spec: UnitSpec,
    ) -> [String]? {
        var canonicalValues: [String] = []
        canonicalValues.reserveCapacity(displayValues.count)

        for raw in displayValues {
            let stripped = stripUnitSuffixIfNeeded(raw, spec: spec)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                canonicalValues.append("")
                continue
            }

            guard let canonical = toCanonical(displayValueText: trimmed, from: unit, spec: spec) else {
                return nil
            }
            canonicalValues.append(canonical)
        }

        return canonicalValues
    }

    private static func parseDecimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if number == .notANumber {
            return "0"
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 12
        formatter.decimalSeparator = "."
        return formatter.string(from: number) ?? number.stringValue
    }
}

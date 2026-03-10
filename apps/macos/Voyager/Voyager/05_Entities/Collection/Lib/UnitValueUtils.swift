import Foundation

enum UnitValueUtils {
    struct UnitOption: Equatable, Sendable {
        let code: String
        let label: String
    }

    struct UnitSpec: Equatable, Sendable {
        let canonicalUnit: String
        let units: [UnitOption]
        let defaultDisplayUnit: String
        fileprivate let factorsToCanonical: [String: Decimal]
    }

    static func spec(for propertyKey: String) -> UnitSpec? {
        switch propertyKey {
        case "size", "file_allocated_size":
            UnitSpec(
                canonicalUnit: "B",
                units: [
                    .init(code: "B", label: "Byte"),
                    .init(code: "KB", label: "KB"),
                    .init(code: "MB", label: "MB"),
                    .init(code: "GB", label: "GB"),
                ],
                defaultDisplayUnit: "Byte",
                factorsToCanonical: [
                    "B": Decimal(1),
                    "KB": Decimal(1024),
                    "MB": Decimal(ByteSizeBucket.oneMB),
                    "GB": Decimal(ByteSizeBucket.oneGB),
                ],
            )
        default:
            nil
        }
    }

    static func supportsUnits(propertyKey: String, valueType: String) -> Bool {
        valueType == "number" && spec(for: propertyKey) != nil
    }

    static func unitCodes(spec: UnitSpec) -> [String] {
        spec.units.map(\.code)
    }

    static func unitLabel(for code: String, spec: UnitSpec) -> String {
        spec.units.first(where: { $0.code == code })?.label ?? code
    }

    static func unitCode(for label: String, spec: UnitSpec) -> String? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return spec.units.first(where: { $0.label.lowercased() == normalized })?.code
    }

    static func defaultDisplayUnitCode(spec: UnitSpec) -> String {
        unitCode(for: spec.defaultDisplayUnit, spec: spec) ?? spec.canonicalUnit
    }

    static func toCanonical(
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

    static func fromCanonical(
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

    static func stripUnitSuffixIfNeeded(_ text: String, spec: UnitSpec) -> String {
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

    static func strippedDisplayValues(_ values: [String], spec: UnitSpec) -> [String] {
        values.map { stripUnitSuffixIfNeeded($0, spec: spec) }
    }

    static func toCanonicalValues(
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

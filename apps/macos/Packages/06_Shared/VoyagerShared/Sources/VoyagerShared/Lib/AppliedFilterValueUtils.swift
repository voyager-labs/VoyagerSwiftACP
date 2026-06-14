import Foundation

public enum AppliedFilterValueUtils {
    public static let recentsSinceAnyOpenedOffset = -1_000_000
    public static let recentsSinceAnyOpenedLiteral = todayFunctionLiteral(offset: recentsSinceAnyOpenedOffset)

    private static let todayFunctionPrefix = "$time.today("
    private static let functionSuffix = ")"

    public static func todayFunctionLiteral(offset: Int) -> String {
        "\(todayFunctionPrefix)\(offset)\(functionSuffix)"
    }

    public static func todayFunctionOffset(for value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(todayFunctionPrefix), text.hasSuffix(functionSuffix) else {
            return nil
        }
        let offsetText = String(text.dropFirst(todayFunctionPrefix.count).dropLast())
        return Int(offsetText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func isTodayFunctionLiteral(_ value: String) -> Bool {
        todayFunctionOffset(for: value) != nil
    }

    public static func stringValues(from value: JSONValue?, valueUIKind: String) -> [String]? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            if isDateValueUIKind(valueUIKind) {
                guard let normalized = normalizeDateString(text, valueUIKind: valueUIKind) else { return nil }
                return [normalized]
            }
            return [normalizeDateString(text, valueUIKind: valueUIKind) ?? text]
        case let .number(number):
            return [formatNumber(number)]
        case let .bool(flag):
            return [flag ? "true" : "false"]
        case let .array(values):
            let strings = values.compactMap { stringValue(from: $0, valueUIKind: valueUIKind) }
            if isDateValueUIKind(valueUIKind), strings.count != values.count {
                return nil
            }
            return strings.isEmpty ? nil : strings
        case .object, .null:
            return nil
        }
    }

    public static func stringValue(from value: JSONValue, valueUIKind: String) -> String? {
        switch value {
        case let .string(text):
            if isDateValueUIKind(valueUIKind) {
                return normalizeDateString(text, valueUIKind: valueUIKind)
            }
            return normalizeDateString(text, valueUIKind: valueUIKind) ?? text
        case let .number(number):
            return formatNumber(number)
        case let .bool(flag):
            return flag ? "true" : "false"
        case .array, .object, .null:
            return nil
        }
    }

    // MARK: - Private

    private static func normalizeDateString(_ text: String, valueUIKind: String) -> String? {
        switch valueUIKind {
        case "singleDate":
            if let literal = RelativeDateConditionLiteral(canonicalLiteral: text) {
                return literal.encodedLiteral()
            }
            if isTodayFunctionLiteral(text) {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let date = DateNormalizerUtils.parseDate(text) else { return nil }
            return DateNormalizerUtils.formatDateOnly(date)
        case "rangeDate":
            guard let date = DateNormalizerUtils.parseDate(text) else { return nil }
            return DateNormalizerUtils.formatDateOnly(date)
        default:
            return nil
        }
    }

    private static func isDateValueUIKind(_ valueUIKind: String) -> Bool {
        valueUIKind == "singleDate" || valueUIKind == "rangeDate"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

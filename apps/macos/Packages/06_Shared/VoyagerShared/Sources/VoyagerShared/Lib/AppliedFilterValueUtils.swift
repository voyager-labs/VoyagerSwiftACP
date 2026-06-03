import Foundation

public enum AppliedFilterValueUtils {
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
            if let relativeDate = canonicalRelativeDateLiteral(text) {
                return relativeDate
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

    private static func canonicalRelativeDateLiteral(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6,
              parts[0] == "voyager.relativeDate",
              parts[1] == "v1",
              ["past", "future"].contains(parts[2]),
              let amount = Int(parts[3]),
              amount > 0,
              ["day", "week", "month", "year"].contains(parts[4]),
              let anchorDate = DateNormalizerUtils.parseDate(parts[5]),
              DateNormalizerUtils.formatDateOnly(anchorDate) == parts[5]
        else {
            return nil
        }
        return parts.joined(separator: ":")
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

import Foundation

public enum AppliedFilterValueUtils {
    public static func stringValues(from value: JSONValue?, valueUIKind: String) -> [String]? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            return [normalizeDateString(text, valueUIKind: valueUIKind) ?? text]
        case let .number(number):
            return [formatNumber(number)]
        case let .bool(flag):
            return [flag ? "true" : "false"]
        case let .array(values):
            let strings = values.compactMap { stringValue(from: $0, valueUIKind: valueUIKind) }
            return strings.isEmpty ? nil : strings
        case .object, .null:
            return nil
        }
    }

    public static func stringValue(from value: JSONValue, valueUIKind: String) -> String? {
        switch value {
        case let .string(text):
            normalizeDateString(text, valueUIKind: valueUIKind) ?? text
        case let .number(number):
            formatNumber(number)
        case let .bool(flag):
            flag ? "true" : "false"
        case .array, .object, .null:
            nil
        }
    }

    // MARK: - Private

    private static func normalizeDateString(_ text: String, valueUIKind: String) -> String? {
        switch valueUIKind {
        case "singleDate", "rangeDate":
            guard let date = DateNormalizerUtils.parseDate(text) else { return nil }
            return DateNormalizerUtils.formatDateOnly(date)
        default:
            return nil
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

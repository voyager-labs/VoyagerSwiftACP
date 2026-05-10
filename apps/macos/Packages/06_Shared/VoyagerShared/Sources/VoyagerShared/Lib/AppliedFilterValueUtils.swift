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
            guard let date = parseDate(text) else { return nil }
            return formatDateOnly(date)
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

    // MARK: - Inlined date helpers (from ValueNormalizerUtils)

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private nonisolated(unsafe) static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private nonisolated(unsafe) static let dateTimeSpaceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func parseDate(_ text: String) -> Date? {
        if let date = isoFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateTimeFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateTimeSpaceFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateOnlyFormatter.date(from: text) { return normalizedDay(date) }
        return nil
    }

    private static func formatDateOnly(_ date: Date) -> String {
        dateOnlyFormatter.string(from: normalizedDay(date))
    }

    private static func normalizedDay(_ date: Date) -> Date {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let comps = localCalendar.dateComponents([.year, .month, .day], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) { utcCalendar.timeZone = utc }
        return utcCalendar.date(from: comps) ?? date
    }
}

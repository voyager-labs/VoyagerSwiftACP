import Foundation

public enum DateNormalizerUtils {
    // MARK: - Formatters (private, used internally)

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated(unsafe) private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    nonisolated(unsafe) private static let dateTimeSpaceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - Public API

    /// Normalize a date to UTC midnight using the user's local calendar components.
    public static func normalizedDay(_ date: Date) -> Date {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let comps = localCalendar.dateComponents([.year, .month, .day], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) { utcCalendar.timeZone = utc }
        return utcCalendar.date(from: comps) ?? date
    }

    /// Parse a date string in ISO8601, dateTime, dateTimeSpace, or dateOnly format.
    public static func parseDate(_ text: String) -> Date? {
        if let date = isoFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateTimeFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateTimeSpaceFormatter.date(from: text) { return normalizedDay(date) }
        if let date = dateOnlyFormatter.date(from: text) { return normalizedDay(date) }
        return nil
    }

    /// Format a date as "yyyy-MM-dd" after normalizing to UTC midnight.
    public static func formatDateOnly(_ date: Date) -> String {
        dateOnlyFormatter.string(from: normalizedDay(date))
    }

    /// Format a date as full ISO8601 after normalizing to UTC midnight.
    public static func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: normalizedDay(date))
    }
}

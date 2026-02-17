import Foundation

enum SearchDateUtils {
    private nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func parseDateLiteral(_ literal: String) -> Date? {
        var text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$time.iso("), text.hasSuffix(")") {
            text = String(text.dropFirst(10).dropLast())
        }

        if isDateOnlyLiteral(text) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }

        if let epochSeconds = Double(text) {
            return Date(timeIntervalSince1970: epochSeconds)
        }

        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso8601WithFractional.date(from: text) {
            return parsed
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        return iso8601.date(from: text)
    }

    static func dayRange(for literal: String) -> (Date, Date)? {
        guard let parsed = parseDateLiteral(literal) else {
            return nil
        }
        return dayRange(for: parsed)
    }

    static func dayRange(for date: Date) -> (Date, Date)? {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    static func dayLiteral(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isDateOnlyLiteral(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 10 else { return false }
        for (index, char) in chars.enumerated() {
            switch index {
            case 4, 7:
                if char != "-" { return false }
            default:
                if char.isNumber == false { return false }
            }
        }
        return true
    }
}

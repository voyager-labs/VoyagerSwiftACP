import Foundation

enum SearchDateUtils {
    private static let utcTimeZone: TimeZone = .init(secondsFromGMT: 0) ?? .gmt

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = utcTimeZone
        return calendar
    }()

    static func parseDateLiteral(_ literal: String) -> Date? {
        var text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$time.iso("), text.hasSuffix(")") {
            text = String(text.dropFirst(10).dropLast())
        }

        if let resolvedToday = resolveTodayLiteral(text) {
            return resolvedToday
        }

        if isDateOnlyLiteral(text) {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = utcTimeZone
            formatter.formatOptions = [.withFullDate]
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

    static func todayOffset(for literal: String) -> Int? {
        let text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("$time.today("), text.hasSuffix(")") else {
            return nil
        }
        let offsetText = String(text.dropFirst("$time.today(".count).dropLast())
        return Int(offsetText)
    }

    static func resolveTodayLiteral(_ literal: String, now: Date = Date()) -> Date? {
        guard let offset = todayOffset(for: literal),
              let start = dayRange(for: now)?.0
        else {
            return nil
        }
        return calendar.date(byAdding: .day, value: offset, to: start)
    }

    static func dayLiteral(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utcTimeZone
        formatter.formatOptions = [.withFullDate]
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

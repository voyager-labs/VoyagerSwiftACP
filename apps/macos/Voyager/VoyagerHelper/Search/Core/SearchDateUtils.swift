import Foundation
import VoyagerShared

enum SearchDateUtils {
    private static let utcTimeZone: TimeZone = .init(secondsFromGMT: 0) ?? .gmt

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = utcTimeZone
        return calendar
    }()

    static func parseDateLiteral(_ literal: String) -> Date? {
        let text = normalizeTimeLiteral(literal)

        if let resolvedToday = resolveTodayLiteral(text) {
            return resolvedToday
        }

        return parseAbsoluteDateLiteral(text)
    }

    static func resolveDateLiteral(_ literal: String, now: Date = Date()) -> Date? {
        let text = normalizeTimeLiteral(literal)

        if let offset = todayOffset(for: text), isTodayLiteral(text) {
            return resolveTodayOffset(offset, now: now)
        }

        if let relative = RelativeDateConditionLiteral.parse(text) {
            return relative.resolve(now: now, calendar: calendar)
        }

        return parseAbsoluteDateLiteral(text)
    }

    static func todayOffset(for literal: String) -> Int? {
        let text = normalizeTimeLiteral(literal)

        if isTodayLiteral(text) {
            let rawOffset = String(text.dropFirst("$time.today(".count).dropLast())
            return Int(rawOffset.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let relative = RelativeDateConditionLiteral.parse(text) else {
            return nil
        }

        let sign = relative.direction == .past ? -1 : 1
        switch relative.unit {
        case .day:
            return sign * relative.amount
        case .week:
            return sign * relative.amount * 7
        case .month, .year:
            return nil
        }
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

    static func resolveTodayLiteral(_ literal: String, now: Date = Date()) -> Date? {
        let text = normalizeTimeLiteral(literal)
        guard isTodayLiteral(text),
              let offset = todayOffset(for: text)
        else {
            return nil
        }
        return resolveTodayOffset(offset, now: now)
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

    private static func isTodayLiteral(_ text: String) -> Bool {
        text.hasPrefix("$time.today(") && text.hasSuffix(")")
    }

    private static func resolveTodayOffset(_ offset: Int, now: Date) -> Date? {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: start)
    }

    private static func normalizeTimeLiteral(_ literal: String) -> String {
        var text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$time.iso("), text.hasSuffix(")") {
            text = String(text.dropFirst(10).dropLast())
        }
        return text
    }

    private static func parseAbsoluteDateLiteral(_ text: String) -> Date? {
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
}

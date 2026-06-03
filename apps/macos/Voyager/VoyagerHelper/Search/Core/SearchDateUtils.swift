import Foundation

enum SearchDateUtils {
    private enum RelativeDirection: String {
        case past
        case future
    }

    private enum RelativeUnit: String {
        case day
        case week
        case month
        case year

        var calendarComponent: Calendar.Component {
            switch self {
            case .day:
                .day
            case .week:
                .weekOfYear
            case .month:
                .month
            case .year:
                .year
            }
        }
    }

    private struct RelativeDateLiteral {
        let direction: RelativeDirection
        let amount: Int
        let unit: RelativeUnit
    }

    private static let utcTimeZone: TimeZone = .init(secondsFromGMT: 0) ?? .gmt

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = utcTimeZone
        return calendar
    }()

    static func parseDateLiteral(_ literal: String) -> Date? {
        let text = normalizeTimeLiteral(literal)

        return parseAbsoluteDateLiteral(text)
    }

    static func resolveDateLiteral(_ literal: String, now: Date = Date()) -> Date? {
        let text = normalizeTimeLiteral(literal)

        if let offset = todayOffset(for: text) {
            return resolveTodayOffset(offset, now: now)
        }

        if let relative = parseRelativeDateLiteral(text) {
            return resolveRelativeDateLiteral(relative, now: now)
        }

        return parseAbsoluteDateLiteral(text)
    }

    static func todayOffset(for literal: String) -> Int? {
        let text = normalizeTimeLiteral(literal)

        if text.hasPrefix("$time.today("), text.hasSuffix(")") {
            let rawOffset = String(text.dropFirst(12).dropLast())
            return Int(rawOffset.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let relative = parseRelativeDateLiteral(text) else {
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

    private static func resolveTodayOffset(_ offset: Int, now: Date) -> Date? {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: start)
    }

    private static func resolveRelativeDateLiteral(_ literal: RelativeDateLiteral, now: Date) -> Date? {
        let start = calendar.startOfDay(for: now)
        let signedAmount = literal.direction == .past ? -literal.amount : literal.amount
        return calendar.date(byAdding: literal.unit.calendarComponent, value: signedAmount, to: start)
    }

    private static func parseRelativeDateLiteral(_ text: String) -> RelativeDateLiteral? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6,
              parts[0] == "voyager.relativeDate",
              parts[1] == "v1",
              let direction = RelativeDirection(rawValue: parts[2]),
              let amount = Int(parts[3]),
              amount > 0,
              let unit = RelativeUnit(rawValue: parts[4]),
              isDateOnlyLiteral(parts[5])
        else {
            return nil
        }

        return RelativeDateLiteral(direction: direction, amount: amount, unit: unit)
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

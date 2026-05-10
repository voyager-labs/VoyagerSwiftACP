import Foundation

public enum DateGroupBucket: Hashable, Sendable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(Int)
    case year(Int)

    public var priority: Int {
        switch self {
        case .today:
            0
        case .yesterday:
            1
        case .previous7Days:
            2
        case .previous30Days:
            3
        case .month:
            4
        case .year:
            5
        }
    }

    public static func bucket(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateGroupBucket {
        if calendar.isDateInToday(date) {
            return .today
        }

        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        let itemDate = calendar.startOfDay(for: date)
        let weekAgoDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -8, to: now) ?? now)
        let yesterdayDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        if itemDate >= weekAgoDate, itemDate <= yesterdayDate {
            return .previous7Days
        }

        let monthAgoDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -37, to: now) ?? now)
        if itemDate >= monthAgoDate, itemDate < weekAgoDate {
            return .previous30Days
        }

        let itemYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        if itemYear == currentYear {
            return .month(calendar.component(.month, from: date))
        }

        return .year(itemYear)
    }

    public static func ordered(_ lhs: DateGroupBucket, _ rhs: DateGroupBucket) -> Bool {
        let lhsPriority = lhs.priority
        let rhsPriority = rhs.priority
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        switch (lhs, rhs) {
        case let (.month(lhsMonth), .month(rhsMonth)):
            return lhsMonth > rhsMonth
        case let (.year(lhsYear), .year(rhsYear)):
            return lhsYear > rhsYear
        default:
            return false
        }
    }
}

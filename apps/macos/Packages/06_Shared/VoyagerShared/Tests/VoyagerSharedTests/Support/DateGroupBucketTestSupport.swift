import Foundation
import XCTest

enum DateGroupBucketTestSupport {
    static func fixedCalendar() -> Calendar {
        Calendar(identifier: .gregorian)
    }

    static func fixedNow(calendar: Calendar) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 10
        components.hour = 12
        components.calendar = calendar
        return try XCTUnwrap(components.date)
    }

    static func dateAt(hour: Int, minute: Int, calendar: Calendar) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 10
        components.hour = hour
        components.minute = minute
        components.calendar = calendar
        return try XCTUnwrap(components.date)
    }

    static func date(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = calendar
        return try XCTUnwrap(components.date)
    }
}

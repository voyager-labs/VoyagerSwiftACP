import Foundation
import VoyagerShared
import XCTest

final class DateGroupBucketTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        // Fixed date: 2026-05-10 12:00:00 UTC
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 10
        comps.hour = 12
        comps.calendar = calendar
        now = comps.date
    }

    override func tearDown() {
        now = nil
        calendar = nil
        super.tearDown()
    }

    // MARK: - Bucket classification

    func testTodayReturnsToday() {
        let date = dateAt(hour: 8, minute: 0)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .today)
    }

    func testYesterdayReturnsYesterday() {
        let date = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .yesterday)
    }

    func testThreeDaysAgoReturnsPrevious7Days() {
        let date = calendar.date(byAdding: .day, value: -3, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    func testTenDaysAgoReturnsPrevious30Days() {
        let date = calendar.date(byAdding: .day, value: -10, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    func testSameYearDifferentMonthReturnsMonth() {
        let date = dateFromComponents(year: 2026, month: 2, day: 5)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .month(2))
    }

    func testDifferentYearReturnsYear() {
        let date = dateFromComponents(year: 2024, month: 11, day: 15)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .year(2024))
    }

    // MARK: - Boundary: -8 days (previous7Days lower bound)

    func testEightDaysAgoReturnsPrevious7Days() {
        let date = calendar.date(byAdding: .day, value: -8, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    func testNineDaysAgoReturnsPrevious30Days() {
        let date = calendar.date(byAdding: .day, value: -9, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    // MARK: - Ordering

    func testOrderedTodayBeforeYesterday() {
        XCTAssertTrue(DateGroupBucket.ordered(.today, .yesterday))
        XCTAssertFalse(DateGroupBucket.ordered(.yesterday, .today))
    }

    func testOrderedYesterdayBeforePrevious7Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.yesterday, .previous7Days))
    }

    func testOrderedPrevious7DaysBeforePrevious30Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous7Days, .previous30Days))
    }

    func testOrderedPrevious30DaysBeforeMonth() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous30Days, .month(3)))
    }

    func testOrderedMonthBeforeYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.month(1), .year(2025)))
    }

    func testOrderedHigherMonthBeforeLowerMonth() {
        // Within same category, higher month value comes first
        XCTAssertTrue(DateGroupBucket.ordered(.month(5), .month(3)))
        XCTAssertFalse(DateGroupBucket.ordered(.month(3), .month(5)))
    }

    func testOrderedHigherYearBeforeLowerYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.year(2025), .year(2024)))
        XCTAssertFalse(DateGroupBucket.ordered(.year(2024), .year(2025)))
    }

    // MARK: - Helpers

    private func dateAt(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 10
        comps.hour = hour
        comps.minute = minute
        comps.calendar = calendar
        return comps.date!
    }

    private func dateFromComponents(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.calendar = calendar
        return comps.date!
    }
}

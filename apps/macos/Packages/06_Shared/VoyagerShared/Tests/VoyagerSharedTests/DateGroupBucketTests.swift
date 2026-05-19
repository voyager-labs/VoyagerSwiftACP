import Foundation
import VoyagerShared
import XCTest

final class DateGroupBucketTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        // 고정 날짜: 2026-05-10 12:00:00 UTC
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

    // MARK: - 버킷 분류

    /// 오늘 날짜는 today 버킷에 들어가는지 검증
    func testTodayReturnsToday() {
        let date = dateAt(hour: 8, minute: 0)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .today)
    }

    /// 하루 전은 yesterday 버킷에 들어가는지 검증
    func testYesterdayReturnsYesterday() {
        let date = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .yesterday)
    }

    /// 3일 전은 previous7Days 버킷에 들어가는지 검증
    func testThreeDaysAgoReturnsPrevious7Days() {
        let date = calendar.date(byAdding: .day, value: -3, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    /// 10일 전은 previous30Days 버킷에 들어가는지 검증
    func testTenDaysAgoReturnsPrevious30Days() {
        let date = calendar.date(byAdding: .day, value: -10, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    /// 같은 해의 다른 달은 month 버킷으로 그룹화되는지 검증
    func testSameYearDifferentMonthReturnsMonth() {
        let date = dateFromComponents(year: 2026, month: 2, day: 5)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .month(2))
    }

    /// 다른 해는 year 버킷으로 그룹화되는지 검증
    func testDifferentYearReturnsYear() {
        let date = dateFromComponents(year: 2024, month: 11, day: 15)
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .year(2024))
    }

    // MARK: - 경계값: -8일 (previous7Days 하한)

    /// -8일 경계가 previous7Days에 포함되는지 검증
    func testEightDaysAgoReturnsPrevious7Days() {
        let date = calendar.date(byAdding: .day, value: -8, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    /// -9일 경계가 previous30Days로 넘어가는지 검증
    func testNineDaysAgoReturnsPrevious30Days() {
        let date = calendar.date(byAdding: .day, value: -9, to: now)!
        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    // MARK: - 정렬

    /// today가 yesterday보다 앞에 정렬되는지 검증
    func testOrderedTodayBeforeYesterday() {
        XCTAssertTrue(DateGroupBucket.ordered(.today, .yesterday))
        XCTAssertFalse(DateGroupBucket.ordered(.yesterday, .today))
    }

    /// yesterday가 previous7Days보다 앞에 정렬되는지 검증
    func testOrderedYesterdayBeforePrevious7Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.yesterday, .previous7Days))
    }

    /// previous7Days가 previous30Days보다 앞에 정렬되는지 검증
    func testOrderedPrevious7DaysBeforePrevious30Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous7Days, .previous30Days))
    }

    /// previous30Days가 month보다 앞에 정렬되는지 검증
    func testOrderedPrevious30DaysBeforeMonth() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous30Days, .month(3)))
    }

    /// month가 year보다 앞에 정렬되는지 검증
    func testOrderedMonthBeforeYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.month(1), .year(2025)))
    }

    /// 같은 달 범주에서는 숫자가 큰 달이 먼저 오도록 정렬되는지 검증
    func testOrderedHigherMonthBeforeLowerMonth() {
        // 같은 카테고리에서는 월 값이 큰 항목이 먼저 정렬됨
        XCTAssertTrue(DateGroupBucket.ordered(.month(5), .month(3)))
        XCTAssertFalse(DateGroupBucket.ordered(.month(3), .month(5)))
    }

    /// 같은 연도 범주에서는 숫자가 큰 연도가 먼저 오도록 정렬되는지 검증
    func testOrderedHigherYearBeforeLowerYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.year(2025), .year(2024)))
        XCTAssertFalse(DateGroupBucket.ordered(.year(2024), .year(2025)))
    }

    // MARK: - 도우미

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

import Foundation
@testable import VoyagerShared
import XCTest

final class CBW005ChatSessionContinuityDateGroupBucketTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        calendar = DateGroupBucketTestSupport.fixedCalendar()
        now = try DateGroupBucketTestSupport.fixedNow(calendar: calendar)
    }

    override func tearDown() {
        now = nil
        calendar = nil
        super.tearDown()
    }

    // MARK: - CBW-005-show_chat_session_list

    /// CBW-005-show_chat_session_list: today bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 오늘 항목이 today 버킷으로 분류되는지 검증합니다.
    /// - 검증 내용: 기준일과 같은 날짜의 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 고정 기준일의 같은 날 항목
    /// - 기대 결과: `.today` 버킷 반환
    func testTodayReturnsToday() throws {
        let date = try DateGroupBucketTestSupport.dateAt(hour: 8, minute: 0, calendar: calendar)

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .today)
    }

    /// CBW-005-show_chat_session_list: yesterday bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 하루 전 항목이 yesterday 버킷으로 분류되는지 검증합니다.
    /// - 검증 내용: 기준일 하루 전 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 기준 하루 전 날짜
    /// - 기대 결과: `.yesterday` 버킷 반환
    func testYesterdayReturnsYesterday() throws {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .yesterday)
    }

    /// CBW-005-show_chat_session_list: previous 7 days bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 최근 7일 범위 항목이 previous7Days 버킷에 들어가는지 검증합니다.
    /// - 검증 내용: 기준일 3일 전 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 기준 3일 전 날짜
    /// - 기대 결과: `.previous7Days` 버킷 반환
    func testThreeDaysAgoReturnsPrevious7Days() throws {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    /// CBW-005-show_chat_session_list: previous 30 days bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 최근 30일 범위 항목이 previous30Days 버킷에 들어가는지 검증합니다.
    /// - 검증 내용: 기준일 10일 전 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 기준 10일 전 날짜
    /// - 기대 결과: `.previous30Days` 버킷 반환
    func testTenDaysAgoReturnsPrevious30Days() throws {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now))

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    /// CBW-005-show_chat_session_list: same-year month bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 같은 해의 다른 달 항목이 month 버킷으로 묶이는지 검증합니다.
    /// - 검증 내용: 기준일과 같은 해의 2월 항목 bucket 계산
    /// - 사전 조건: 2026-02-05 날짜
    /// - 기대 결과: `.month(2)` 버킷 반환
    func testSameYearDifferentMonthReturnsMonth() throws {
        let date = try DateGroupBucketTestSupport.date(year: 2026, month: 2, day: 5, calendar: calendar)

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .month(2))
    }

    /// CBW-005-show_chat_session_list: different-year bucket classification
    /// 채팅 세션 목록 날짜 그룹에서 다른 해 항목이 year 버킷으로 묶이는지 검증합니다.
    /// - 검증 내용: 기준일과 다른 해의 항목 bucket 계산
    /// - 사전 조건: 2024-11-15 날짜
    /// - 기대 결과: `.year(2024)` 버킷 반환
    func testDifferentYearReturnsYear() throws {
        let date = try DateGroupBucketTestSupport.date(year: 2024, month: 11, day: 15, calendar: calendar)

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .year(2024))
    }

    /// CBW-005-show_chat_session_list: previous 7 days lower boundary
    /// 채팅 세션 목록 날짜 그룹에서 previous7Days 하한 경계가 유지되는지 검증합니다.
    /// - 검증 내용: 기준일 8일 전 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 기준 8일 전 날짜
    /// - 기대 결과: `.previous7Days` 버킷 반환
    func testEightDaysAgoReturnsPrevious7Days() throws {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now))

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous7Days)
    }

    /// CBW-005-show_chat_session_list: previous 30 days boundary transition
    /// 채팅 세션 목록 날짜 그룹에서 previous7Days 다음 날짜가 previous30Days로 넘어가는지 검증합니다.
    /// - 검증 내용: 기준일 9일 전 항목 bucket 계산
    /// - 사전 조건: 2026-05-10 기준 9일 전 날짜
    /// - 기대 결과: `.previous30Days` 버킷 반환
    func testNineDaysAgoReturnsPrevious30Days() throws {
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -9, to: now))

        XCTAssertEqual(DateGroupBucket.bucket(for: date, now: now, calendar: calendar), .previous30Days)
    }

    /// CBW-005-show_chat_session_list: today before yesterday ordering
    /// 채팅 세션 목록 날짜 그룹이 최신 날짜 버킷을 먼저 정렬하는지 검증합니다.
    /// - 검증 내용: today와 yesterday 버킷 간 정렬 관계
    /// - 사전 조건: today/yesterday bucket 값
    /// - 기대 결과: today가 yesterday보다 앞에 정렬
    func testOrderedTodayBeforeYesterday() {
        XCTAssertTrue(DateGroupBucket.ordered(.today, .yesterday))
        XCTAssertFalse(DateGroupBucket.ordered(.yesterday, .today))
    }

    /// CBW-005-show_chat_session_list: yesterday before previous 7 days ordering
    /// 채팅 세션 목록 날짜 그룹에서 yesterday가 previous7Days보다 앞에 정렬되는지 검증합니다.
    /// - 검증 내용: yesterday와 previous7Days 버킷 간 정렬 관계
    /// - 사전 조건: yesterday/previous7Days bucket 값
    /// - 기대 결과: yesterday가 previous7Days보다 앞에 정렬
    func testOrderedYesterdayBeforePrevious7Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.yesterday, .previous7Days))
    }

    /// CBW-005-show_chat_session_list: previous 7 days before previous 30 days ordering
    /// 채팅 세션 목록 날짜 그룹에서 previous7Days가 previous30Days보다 앞에 정렬되는지 검증합니다.
    /// - 검증 내용: previous7Days와 previous30Days 버킷 간 정렬 관계
    /// - 사전 조건: previous7Days/previous30Days bucket 값
    /// - 기대 결과: previous7Days가 previous30Days보다 앞에 정렬
    func testOrderedPrevious7DaysBeforePrevious30Days() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous7Days, .previous30Days))
    }

    /// CBW-005-show_chat_session_list: previous 30 days before month ordering
    /// 채팅 세션 목록 날짜 그룹에서 previous30Days가 월 버킷보다 앞에 정렬되는지 검증합니다.
    /// - 검증 내용: previous30Days와 month 버킷 간 정렬 관계
    /// - 사전 조건: previous30Days/month bucket 값
    /// - 기대 결과: previous30Days가 month보다 앞에 정렬
    func testOrderedPrevious30DaysBeforeMonth() {
        XCTAssertTrue(DateGroupBucket.ordered(.previous30Days, .month(3)))
    }

    /// CBW-005-show_chat_session_list: month before year ordering
    /// 채팅 세션 목록 날짜 그룹에서 월 버킷이 연도 버킷보다 앞에 정렬되는지 검증합니다.
    /// - 검증 내용: month와 year 버킷 간 정렬 관계
    /// - 사전 조건: month/year bucket 값
    /// - 기대 결과: month가 year보다 앞에 정렬
    func testOrderedMonthBeforeYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.month(1), .year(2025)))
    }

    /// CBW-005-show_chat_session_list: descending month ordering
    /// 채팅 세션 목록 날짜 그룹에서 같은 월 카테고리끼리는 최신 월이 앞서는지 검증합니다.
    /// - 검증 내용: month 버킷 내부 숫자 정렬 관계
    /// - 사전 조건: 서로 다른 month bucket 값
    /// - 기대 결과: 숫자가 큰 월이 작은 월보다 앞에 정렬
    func testOrderedHigherMonthBeforeLowerMonth() {
        XCTAssertTrue(DateGroupBucket.ordered(.month(5), .month(3)))
        XCTAssertFalse(DateGroupBucket.ordered(.month(3), .month(5)))
    }

    /// CBW-005-show_chat_session_list: descending year ordering
    /// 채팅 세션 목록 날짜 그룹에서 같은 연도 카테고리끼리는 최신 연도가 앞서는지 검증합니다.
    /// - 검증 내용: year 버킷 내부 숫자 정렬 관계
    /// - 사전 조건: 서로 다른 year bucket 값
    /// - 기대 결과: 숫자가 큰 연도가 작은 연도보다 앞에 정렬
    func testOrderedHigherYearBeforeLowerYear() {
        XCTAssertTrue(DateGroupBucket.ordered(.year(2025), .year(2024)))
        XCTAssertFalse(DateGroupBucket.ordered(.year(2024), .year(2025)))
    }
}

import Foundation
@testable import VoyagerShared
import XCTest

final class RCL005ChangeCollectionConditionValueRelativeDateLiteralTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let fixedNow = Date(timeIntervalSince1970: 1_747_433_600) // 2025-05-17T00:00:00Z

    // MARK: - RCL-005-change_collection_condition_value

    /// RCL-005-change_collection_condition_value: canonical relative date literal parsing
    /// 컬렉션 조건값 편집에서 저장된 상대 날짜 literal이 안정적으로 복원되는지 검증합니다.
    /// - 검증 내용: `voyager.relativeDate:v1` literal의 direction, amount, unit, anchorDateLiteral 파싱
    /// - 사전 조건: 유효한 canonical relative date literal 문자열
    /// - 기대 결과: 각 구성 요소가 손실 없이 `RelativeDateConditionLiteral`로 복원
    func testParsesCanonicalLiteral() {
        let literal = RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:day:2025-05-17")

        XCTAssertNotNil(literal)
        XCTAssertEqual(literal?.direction, .past)
        XCTAssertEqual(literal?.amount, 3)
        XCTAssertEqual(literal?.unit, .day)
        XCTAssertEqual(literal?.anchorDateLiteral, "2025-05-17")
    }

    /// RCL-005-change_collection_condition_value: invalid relative date literal rejection
    /// 컬렉션 조건값 편집에서 잘못된 상대 날짜 literal이 조건값으로 받아들여지지 않는지 검증합니다.
    /// - 검증 내용: amount, version, unit, anchor format 오류 입력 거부
    /// - 사전 조건: canonical 형식을 벗어난 relative date literal 문자열들
    /// - 기대 결과: 모든 잘못된 입력이 nil로 처리
    func testRejectsInvalidRelativeLiteral() {
        XCTAssertNil(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:0:day:2025-05-17"))
        XCTAssertNil(RelativeDateConditionLiteral.parse("voyager.relativeDate:v2:past:3:day:2025-05-17"))
        XCTAssertNil(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:century:2025-05-17"))
        XCTAssertNil(RelativeDateConditionLiteral.parse("voyager.relativeDate:v1:past:3:day:2025-5-17"))
    }

    /// RCL-005-change_collection_condition_value: canonical relative date literal encoding
    /// 컬렉션 조건값 저장 시 상대 날짜 선택이 canonical literal로 직렬화되는지 검증합니다.
    /// - 검증 내용: direction, amount, unit, anchorDateLiteral이 `voyager.relativeDate:v1` 문자열로 인코딩됨
    /// - 사전 조건: future/week 상대 날짜 조건값 구성 요소
    /// - 기대 결과: 저장 가능한 canonical literal 문자열 반환
    func testEncodesCanonicalLiteral() {
        let encoded = RelativeDateConditionLiteral.encode(
            direction: .future,
            amount: 7,
            unit: .week,
            anchorDateLiteral: "2025-05-17",
        )

        XCTAssertEqual(encoded, "voyager.relativeDate:v1:future:7:week:2025-05-17")
    }

    /// RCL-005-change_collection_condition_value: relative date condition display text
    /// 컬렉션 조건값 UI가 상대 날짜 조건을 사람이 읽을 수 있는 문구로 표시할 수 있는지 검증합니다.
    /// - 검증 내용: past/month literal의 표시 문구 생성
    /// - 사전 조건: 2개월 전 relative date literal
    /// - 기대 결과: `2 months ago` 표시 문자열 반환
    func testDisplayTextIsHumanReadable() {
        let literal = RelativeDateConditionLiteral(
            direction: .past,
            amount: 2,
            unit: .month,
            anchorDateLiteral: "2025-05-17",
        )

        XCTAssertEqual(literal.displayText(), "2 months ago")
    }

    /// RCL-005-change_collection_condition_value: calendar-based relative date resolution
    /// 컬렉션 조건값 실행 시 상대 날짜 literal이 calendar 단위 기준으로 결정되는지 검증합니다.
    /// - 검증 내용: 1개월 전 literal이 고정 기준일에서 calendar month만큼 이동함
    /// - 사전 조건: 2025-05-17 기준 1개월 전 relative date literal
    /// - 기대 결과: resolved date가 2025-04-17
    func testResolveUsesCalendarUnits() {
        let pastMonth = RelativeDateConditionLiteral(
            direction: .past,
            amount: 1,
            unit: .month,
            anchorDateLiteral: "2025-05-17",
        )

        let resolved = pastMonth.resolve(now: fixedNow, calendar: calendar)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(DateNormalizerUtils.formatDateOnly(resolved ?? fixedNow), "2025-04-17")
    }

    /// RCL-005-change_collection_condition_value: forward and backward relative date resolution
    /// 컬렉션 조건값 실행에서 미래/과거 상대 날짜 계산이 deterministic하게 유지되는지 검증합니다.
    /// - 검증 내용: future week와 past day literal의 날짜 계산
    /// - 사전 조건: 2025-05-17 기준 2주 후와 7일 전 relative date literal
    /// - 기대 결과: 각각 2025-05-31, 2025-05-10으로 계산
    func testResolveWeekForwardAndDayBackwardRemainDeterministic() {
        let futureWeek = RelativeDateConditionLiteral(
            direction: .future,
            amount: 2,
            unit: .week,
            anchorDateLiteral: "2025-05-17",
        )
        let pastDay = RelativeDateConditionLiteral(
            direction: .past,
            amount: 7,
            unit: .day,
            anchorDateLiteral: "2025-05-17",
        )

        XCTAssertEqual(
            DateNormalizerUtils.formatDateOnly(futureWeek.resolve(now: fixedNow, calendar: calendar) ?? fixedNow),
            "2025-05-31",
        )
        XCTAssertEqual(
            DateNormalizerUtils.formatDateOnly(pastDay.resolve(now: fixedNow, calendar: calendar) ?? fixedNow),
            "2025-05-10",
        )
    }
}

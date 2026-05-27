@testable import VoyagerWidgetsEntryViewLayout
import XCTest

final class EntryViewLayoutDateFormattingTests: XCTestCase {
    /// 열 너비에 따라 날짜 템플릿이 올바르게 선택되는지 검증
    ///
    /// - 검증 내용: 좁은 열(≤139pt)은 짧은 형식(yMd), 중간(140~219pt)은 MMMd,
    ///   넓은 열(≥220pt)은 전체 형식(yMMMdjm)을 반환
    /// - 사전 조건: EntryListDateFormatting.template(forWidth:)가 세 구간으로 나뉨
    /// - 기대 결과: 각 경계값(139, 140, 219, 220)에서 정확한 템플릿 전환
    /// - 회귀 방지: 잘못된 구간 매핑으로 목록 뷰에서 날짜가 깨지는 버그 방지
    func testTemplateMapping() {
        // < 140pt → yMd (좁은 열: 날짜만 표시)
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 50), "yMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 139), "yMd")

        // 140~219pt → MMMd (중간 열: 월-일 표시)
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 140), "MMMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 219), "MMMd")

        // ≥ 220pt → yMMMdjm (넓은 열: 날짜+시간 표시)
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 220), "yMMMdjm")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 500), "yMMMdjm")

        // width ≤ 0 → 안전한 폴백(yMd): 비정상 너비에도 크래시 없이 최소 형식 반환
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: 0), "yMd")
        XCTAssertEqual(EntryListDateFormatting.template(forWidth: -10), "yMd")
    }

    /// 고정 로케일·타임존에서 실제 포맷팅 결과가 예상 문자열을 포함하는지 검증
    ///
    /// - 검증 내용: 각 너비 구간의 포맷 출력에 핵심 성분(연/월/일)이 포함되는지 확인,
    ///   타임존 차이(UTC vs Asia/Seoul)가 결과에 반영되는지도 검증
    /// - 회귀 방지: 로케일/타임존 처리 오류로 인한 날짜 표시 불일치 방지
    func testFormattingWithFixedLocaleAndTimeZone() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let locale = Locale(identifier: "en_US_POSIX")
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))

        let yMd = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: utc)
        XCTAssertTrue(yMd.contains("11"))
        XCTAssertTrue(yMd.contains("14"))
        XCTAssertTrue(yMd.contains("2023") || yMd.contains("23"))

        let mMMdd = EntryListDateFormatting.format(date, width: 150, locale: locale, timeZone: utc)
        XCTAssertTrue(mMMdd.contains("Nov"))
        XCTAssertTrue(mMMdd.contains("14"))

        let detailedUTC = EntryListDateFormatting.format(date, width: 250, locale: locale, timeZone: utc)
        XCTAssertTrue(detailedUTC.contains("Nov"))
        XCTAssertTrue(detailedUTC.contains("2023") || detailedUTC.contains("23"))

        let detailedSeoul = EntryListDateFormatting.format(date, width: 250, locale: locale, timeZone: seoul)
        XCTAssertNotEqual(detailedUTC, detailedSeoul)
    }

    /// 동일 입력에 대해 반복 포맷팅이 항상 같은 결과를 반환하는지 검증
    ///
    /// - 검증 내용: 같은 date/width/locale/timeZone으로 두 번 포맷팅한 결과가 동일
    /// - 회귀 방지: 내부 캐시나 상태 누적으로 인한 비결정적 출력 방지
    func testRepeatedFormattingIsStable() throws {
        let date = Date()
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let first = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: timeZone)
        let second = EntryListDateFormatting.format(date, width: 100, locale: locale, timeZone: timeZone)
        XCTAssertEqual(first, second)
    }
}

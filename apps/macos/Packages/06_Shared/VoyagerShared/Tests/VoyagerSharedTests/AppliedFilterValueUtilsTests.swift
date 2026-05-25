import VoyagerShared
import XCTest

final class AppliedFilterValueUtilsTests: XCTestCase {
    // MARK: - stringValues (선택적 입력)

    /// 문자열 값은 그대로 배열에 담기는지 검증
    func testStringValueReturnsArrayWithString() {
        let result = AppliedFilterValueUtils.stringValues(from: .string("hello"), valueUIKind: "text")
        XCTAssertEqual(result, ["hello"])
    }

    /// 정수 number는 정수 문자열로 변환되는지 검증
    func testNumberIntegerReturnsStringOfInteger() {
        let result = AppliedFilterValueUtils.stringValues(from: .number(42.0), valueUIKind: "text")
        XCTAssertEqual(result, ["42"])
    }

    /// 소수 number는 소수 문자열을 유지하는지 검증
    func testNumberDecimalReturnsStringOfDecimal() {
        let result = AppliedFilterValueUtils.stringValues(from: .number(3.14), valueUIKind: "text")
        XCTAssertEqual(result, ["3.14"])
    }

    /// boolean true가 문자열 true로 변환되는지 검증
    func testBoolTrueReturnsTrue() {
        let result = AppliedFilterValueUtils.stringValues(from: .bool(true), valueUIKind: "text")
        XCTAssertEqual(result, ["true"])
    }

    /// boolean false가 문자열 false로 변환되는지 검증
    func testBoolFalseReturnsFalse() {
        let result = AppliedFilterValueUtils.stringValues(from: .bool(false), valueUIKind: "text")
        XCTAssertEqual(result, ["false"])
    }

    /// 배열 입력이 내부 값들을 문자열 배열로 평탄화하는지 검증
    func testArrayOfValuesReturnsArrayOfStrings() {
        let value = JSONValue.array([.string("a"), .number(1.0), .bool(true)])
        let result = AppliedFilterValueUtils.stringValues(from: value, valueUIKind: "text")
        XCTAssertEqual(result, ["a", "1", "true"])
    }

    /// nil 입력은 nil을 반환하는지 검증
    func testNilInputReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: nil, valueUIKind: "text")
        XCTAssertNil(result)
    }

    /// 객체 입력은 문자열 값으로 해석되지 않아 nil이 되는지 검증
    func testObjectReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .object(["key": .string("val")]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    /// null 입력은 nil을 반환하는지 검증
    func testNullReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .null, valueUIKind: "text")
        XCTAssertNil(result)
    }

    // MARK: - 날짜 포맷팅

    /// singleDate UI kind에서 ISO 문자열이 날짜 형식으로 변환되는지 검증
    func testDateStringWithSingleDateKindReturnsFormattedDate() {
        // ISO8601 날짜 문자열
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "singleDate")
        // 날짜만 포맷된 문자열을 반환해야 함
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertFalse(result!.first!.contains("T")) // 날짜만 포함하고 시간 성분은 없어야 함
    }

    /// rangeDate UI kind도 날짜 문자열 한 개로 정규화되는지 검증
    func testDateStringWithRangeDateKindReturnsFormattedDate() {
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "rangeDate")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
    }

    /// 날짜가 아닌 UI kind에서는 원본 문자열을 유지하는지 검증
    func testDateStringWithNonDateKindReturnsOriginalString() {
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "text")
        // 원본 문자열을 그대로 반환해야 함
        XCTAssertEqual(result, [isoString])
    }

    // MARK: - stringValue (비선택적 입력)

    /// 단일 stringValue가 문자열을 그대로 반환하는지 검증
    func testStringValueStringReturnsString() {
        let result = AppliedFilterValueUtils.stringValue(from: .string("hello"), valueUIKind: "text")
        XCTAssertEqual(result, "hello")
    }

    /// number 입력을 단일 문자열로 변환하는지 검증
    func testStringValueNumberReturnsString() {
        let result = AppliedFilterValueUtils.stringValue(from: .number(7.0), valueUIKind: "text")
        XCTAssertEqual(result, "7")
    }

    /// boolean true가 단일 문자열 true로 변환되는지 검증
    func testStringValueBoolTrueReturnsTrue() {
        let result = AppliedFilterValueUtils.stringValue(from: .bool(true), valueUIKind: "text")
        XCTAssertEqual(result, "true")
    }

    /// boolean false가 단일 문자열 false로 변환되는지 검증
    func testStringValueBoolFalseReturnsFalse() {
        let result = AppliedFilterValueUtils.stringValue(from: .bool(false), valueUIKind: "text")
        XCTAssertEqual(result, "false")
    }

    /// 배열 입력은 단일 stringValue로 표현되지 않는지 검증
    func testStringValueArrayReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .array([]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    /// 객체 입력은 단일 stringValue로 표현되지 않는지 검증
    func testStringValueObjectReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .object([:]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    /// null 입력은 단일 stringValue로 표현되지 않는지 검증
    func testStringValueNullReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .null, valueUIKind: "text")
        XCTAssertNil(result)
    }

    // MARK: - 빈 배열 경계 케이스

    /// 빈 배열은 선택적 stringValues 결과가 nil이어야 하는지 검증
    func testEmptyArrayReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .array([]), valueUIKind: "text")
        XCTAssertNil(result)
    }
}

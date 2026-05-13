import VoyagerShared
import XCTest

final class AppliedFilterValueUtilsTests: XCTestCase {
    // MARK: - stringValues (optional input)

    func testStringValueReturnsArrayWithString() {
        let result = AppliedFilterValueUtils.stringValues(from: .string("hello"), valueUIKind: "text")
        XCTAssertEqual(result, ["hello"])
    }

    func testNumberIntegerReturnsStringOfInteger() {
        let result = AppliedFilterValueUtils.stringValues(from: .number(42.0), valueUIKind: "text")
        XCTAssertEqual(result, ["42"])
    }

    func testNumberDecimalReturnsStringOfDecimal() {
        let result = AppliedFilterValueUtils.stringValues(from: .number(3.14), valueUIKind: "text")
        XCTAssertEqual(result, ["3.14"])
    }

    func testBoolTrueReturnsTrue() {
        let result = AppliedFilterValueUtils.stringValues(from: .bool(true), valueUIKind: "text")
        XCTAssertEqual(result, ["true"])
    }

    func testBoolFalseReturnsFalse() {
        let result = AppliedFilterValueUtils.stringValues(from: .bool(false), valueUIKind: "text")
        XCTAssertEqual(result, ["false"])
    }

    func testArrayOfValuesReturnsArrayOfStrings() {
        let value = JSONValue.array([.string("a"), .number(1.0), .bool(true)])
        let result = AppliedFilterValueUtils.stringValues(from: value, valueUIKind: "text")
        XCTAssertEqual(result, ["a", "1", "true"])
    }

    func testNilInputReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: nil, valueUIKind: "text")
        XCTAssertNil(result)
    }

    func testObjectReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .object(["key": .string("val")]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    func testNullReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .null, valueUIKind: "text")
        XCTAssertNil(result)
    }

    // MARK: - Date formatting

    func testDateStringWithSingleDateKindReturnsFormattedDate() {
        // ISO8601 date string
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "singleDate")
        // Should return date-only formatted string
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertFalse(result!.first!.contains("T")) // Should be date-only, no time component
    }

    func testDateStringWithRangeDateKindReturnsFormattedDate() {
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "rangeDate")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
    }

    func testDateStringWithNonDateKindReturnsOriginalString() {
        let isoString = "2026-05-10T12:00:00Z"
        let result = AppliedFilterValueUtils.stringValues(from: .string(isoString), valueUIKind: "text")
        // Should return original string unchanged
        XCTAssertEqual(result, [isoString])
    }

    // MARK: - stringValue (non-optional input)

    func testStringValueStringReturnsString() {
        let result = AppliedFilterValueUtils.stringValue(from: .string("hello"), valueUIKind: "text")
        XCTAssertEqual(result, "hello")
    }

    func testStringValueNumberReturnsString() {
        let result = AppliedFilterValueUtils.stringValue(from: .number(7.0), valueUIKind: "text")
        XCTAssertEqual(result, "7")
    }

    func testStringValueBoolTrueReturnsTrue() {
        let result = AppliedFilterValueUtils.stringValue(from: .bool(true), valueUIKind: "text")
        XCTAssertEqual(result, "true")
    }

    func testStringValueBoolFalseReturnsFalse() {
        let result = AppliedFilterValueUtils.stringValue(from: .bool(false), valueUIKind: "text")
        XCTAssertEqual(result, "false")
    }

    func testStringValueArrayReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .array([]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    func testStringValueObjectReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .object([:]), valueUIKind: "text")
        XCTAssertNil(result)
    }

    func testStringValueNullReturnsNil() {
        let result = AppliedFilterValueUtils.stringValue(from: .null, valueUIKind: "text")
        XCTAssertNil(result)
    }

    // MARK: - Empty array edge case

    func testEmptyArrayReturnsNil() {
        let result = AppliedFilterValueUtils.stringValues(from: .array([]), valueUIKind: "text")
        XCTAssertNil(result)
    }
}

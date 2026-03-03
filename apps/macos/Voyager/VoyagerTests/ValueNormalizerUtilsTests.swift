import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ValueNormalizerUtilsTests: XCTestCase {
    func testNormalizeNoneAlwaysReturnsEmptyValues() {
        let result = ValueNormalizerUtils.normalize(
            kind: "none",
            rawValues: ["unexpected"],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, [])
        XCTAssertEqual(result.resetIndices, [])
    }

    func testNormalizeSingleTextTrimsWhitespace() {
        let result = ValueNormalizerUtils.normalize(
            kind: "singleText",
            rawValues: ["  hello  "],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["hello"])
    }

    func testNormalizeSingleTextRequiresNonEmptyValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "singleText",
            rawValues: ["   "],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Value is required.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testNormalizeListTextSplitsByCommaAndNewline() {
        let result = ValueNormalizerUtils.normalize(
            kind: "listText",
            rawValues: [" alpha, beta\ngamma "],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["alpha", "beta", "gamma"])
    }

    func testNormalizeSingleNumberRequiresValidNumber() {
        let invalid = ValueNormalizerUtils.normalize(
            kind: "singleNumber",
            rawValues: ["abc"],
            editingIndex: nil,
        )
        XCTAssertEqual(invalid.errorMessage, "Enter a valid number.")

        let valid = ValueNormalizerUtils.normalize(
            kind: "singleNumber",
            rawValues: [" -10.5 "],
            editingIndex: nil,
        )
        XCTAssertNil(valid.errorMessage)
        XCTAssertEqual(valid.values, ["-10.5"])
    }

    func testNormalizeListNumberRejectsInvalidMember() {
        let result = ValueNormalizerUtils.normalize(
            kind: "listNumber",
            rawValues: ["1,2,xx"],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid numbers.")
        XCTAssertNil(result.values)
    }

    func testNormalizeSingleDateAcceptsIsoAndDateOnly() {
        let iso = ValueNormalizerUtils.normalize(
            kind: "singleDate",
            rawValues: ["2026-02-26T13:45:12Z"],
            editingIndex: nil,
        )
        XCTAssertNil(iso.errorMessage)

        let dateOnly = ValueNormalizerUtils.normalize(
            kind: "singleDate",
            rawValues: ["2026-02-26"],
            editingIndex: nil,
        )
        XCTAssertNil(dateOnly.errorMessage)
    }

    func testNormalizeToggleTrimsAndLowercasesBooleanValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "toggle",
            rawValues: ["  TRUE  "],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["true"])
    }

    func testNormalizeToggleRejectsNonBooleanValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "toggle",
            rawValues: ["yes"],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Enter true or false.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testNormalizeRangeDateAllowsSingleEndpointWithoutError() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["2026-02-26", ""],
            editingIndex: 0,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [1])
    }

    func testNormalizeRangeDateAllowsToOnlyWithoutError() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["", "2026-02-27"],
            editingIndex: 1,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testNormalizeRangeNumberAllowsSingleEndpointWithoutError() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["10", ""],
            editingIndex: 0,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [1])
    }

    func testNormalizeRangeNumberAllowsToOnlyWithoutError() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["", "20"],
            editingIndex: 1,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testNormalizeRangeDateCommitsWhenBothEndpointsValid() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["2026-02-26", "2026-02-27"],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["2026-02-26", "2026-02-27"])
        XCTAssertEqual(result.resetIndices, [])
    }

    func testNormalizeRangeNumberCommitsWhenBothEndpointsValid() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["10", "20"],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["10", "20"])
        XCTAssertEqual(result.resetIndices, [])
    }

    func testNormalizeRangeDateRejectsInvalidDateValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["invalid-date", "2026-02-27"],
            editingIndex: 0,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid dates.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0])
    }

    func testNormalizeRangeDateRejectsInvalidSecondDateValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["2026-02-26", "invalid-date"],
            editingIndex: 1,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid dates.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [1])
    }

    func testNormalizeRangeDateRejectsBothEndpointsInvalid() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["invalid-a", "invalid-b"],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid dates.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0, 1])
    }

    func testNormalizeRangeDateRejectsWhenBothEndpointsEmpty() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["", ""],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Value is required.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0, 1])
    }

    func testNormalizeRangeNumberRejectsInvalidSecondValue() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["10", "xx"],
            editingIndex: 1,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid numbers.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [1])
    }

    func testNormalizeRangeNumberRejectsBothEndpointsInvalid() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["aa", "bb"],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Enter valid numbers.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0, 1])
    }

    func testNormalizeRangeNumberRejectsWhenBothEndpointsEmpty() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["", ""],
            editingIndex: nil,
        )

        XCTAssertEqual(result.errorMessage, "Value is required.")
        XCTAssertNil(result.values)
        XCTAssertEqual(result.resetIndices, [0, 1])
    }

    func testNormalizeRangeDatePreservesExtraArityInput() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeDate",
            rawValues: ["2026-02-26", "2026-02-27", "2026-02-28"],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["2026-02-26", "2026-02-27", "2026-02-28"])
    }

    func testNormalizeRangeNumberPreservesExtraArityInput() {
        let result = ValueNormalizerUtils.normalize(
            kind: "rangeNumber",
            rawValues: ["10", "20", "30"],
            editingIndex: nil,
        )

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.values, ["10", "20", "30"])
    }

    func testFormatDateOnlyStringParsesIsoAndSpaceDateTime() {
        XCTAssertEqual(ValueNormalizerUtils.formatDateOnlyString("2026-02-26T13:45:12Z"), "2026-02-26")
        XCTAssertEqual(ValueNormalizerUtils.formatDateOnlyString("2026-02-27 09:00:00"), "2026-02-27")
    }
}

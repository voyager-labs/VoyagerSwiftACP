import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ConditionChipValueDisplayTests: XCTestCase {
    func testDisplayedValuesForDateUsesPickerValuesWhileEditingSameCondition() {
        let displayed = ConditionChipView.displayedValuesForDate(
            conditionValues: ["2026-02-01", "2026-02-10"],
            conditionPropertyKey: "content_modified_at",
            pickerPropertyKey: "content_modified_at",
            pickerPresented: true,
            pickerValues: ["2026-02-15", ""],
        )

        XCTAssertEqual(displayed, ["2026-02-15", ""])
    }

    func testDisplayedValuesForDateFallsBackWhenPickerClosed() {
        let displayed = ConditionChipView.displayedValuesForDate(
            conditionValues: ["2026-02-01", "2026-02-10"],
            conditionPropertyKey: "content_modified_at",
            pickerPropertyKey: "content_modified_at",
            pickerPresented: false,
            pickerValues: ["2026-02-15", ""],
        )

        XCTAssertEqual(displayed, ["2026-02-01", "2026-02-10"])
    }

    func testFormattedValueTextForDateRangeUsesTilde() {
        let text = ConditionChipView.formattedValueText(
            values: ["2026-02-01", "2026-02-10"],
            propertyKey: "content_modified_at",
            valueType: "date",
            rangeSeparator: "~",
        )

        XCTAssertEqual(text, "2026-02-01 ~ 2026-02-10")
    }

    func testFormattedValueTextForDateRangeCollapsesWhenSameDate() {
        let text = ConditionChipView.formattedValueText(
            values: ["2026-02-01", "2026-02-01"],
            propertyKey: "content_modified_at",
            valueType: "date",
            rangeSeparator: "~",
        )

        XCTAssertEqual(text, "2026-02-01")
    }

    func testFormattedValueTextForNumberRangeUsesTilde() {
        let text = ConditionChipView.formattedValueText(
            values: ["10", "20"],
            propertyKey: "file_allocated_size",
            valueType: "number",
            rangeSeparator: "~",
        )

        XCTAssertEqual(text, "10 ~ 20")
    }
}

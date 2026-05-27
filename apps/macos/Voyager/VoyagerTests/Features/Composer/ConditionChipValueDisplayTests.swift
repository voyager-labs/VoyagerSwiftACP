import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

/// 조건 칩 값 표시 — 날짜/숫자 범위 렌더링 포맷을 검증.
@MainActor
final class ConditionChipValueDisplayTests: XCTestCase {
    private func makeCondition(
        propertyKey: String,
        valueType: String,
        values: [String],
    ) -> Condition {
        Condition(
            propertyKey: propertyKey,
            propertyLabel: propertyKey,
            propertyType: valueType,
            operatorCode: nil,
            operatorLabel: nil,
            operatorValueArity: nil,
            operatorValueUIKind: nil,
            valueType: valueType,
            values: values,
        )
    }

    /// testDisplayedValuesForDateUsesPickerValuesWhileEditingSameCondition 테스트 동작을 검증한다.
    func testDisplayedValuesForDateUsesPickerValuesWhileEditingSameCondition() {
        let displayed = ConditionChipDisplayUtils.displayedValuesForDate(
            conditionValues: ["2026-02-01", "2026-02-10"],
            conditionPropertyKey: "content_modified_at",
            pickerPropertyKey: "content_modified_at",
            pickerPresented: true,
            pickerValues: ["2026-02-15", ""],
        )

        XCTAssertEqual(displayed, ["2026-02-15", ""])
    }

    /// testDisplayedValuesForDateFallsBackWhenPickerClosed 테스트 동작을 검증한다.
    func testDisplayedValuesForDateFallsBackWhenPickerClosed() {
        let displayed = ConditionChipDisplayUtils.displayedValuesForDate(
            conditionValues: ["2026-02-01", "2026-02-10"],
            conditionPropertyKey: "content_modified_at",
            pickerPropertyKey: "content_modified_at",
            pickerPresented: false,
            pickerValues: ["2026-02-15", ""],
        )

        XCTAssertEqual(displayed, ["2026-02-01", "2026-02-10"])
    }

    /// testFormattedValueTextForDateRangeUsesHyphen 테스트 동작을 검증한다.
    func testFormattedValueTextForDateRangeUsesHyphen() {
        let text = ConditionChipDisplayUtils.displayValueText(for: makeCondition(
            propertyKey: "content_modified_at",
            valueType: "date",
            values: ["2026-02-01", "2026-02-10"],
        ))

        XCTAssertEqual(text, "2026-02-01 ~ 2026-02-10")
    }

    /// testFormattedValueTextForDateRangeCollapsesWhenSameDate 테스트 동작을 검증한다.
    func testFormattedValueTextForDateRangeCollapsesWhenSameDate() {
        let text = ConditionChipDisplayUtils.displayValueText(for: makeCondition(
            propertyKey: "content_modified_at",
            valueType: "date",
            values: ["2026-02-01", "2026-02-01"],
        ))

        XCTAssertEqual(text, "2026-02-01")
    }

    /// testFormattedValueTextForNumberRangeUsesHyphen 테스트 동작을 검증한다.
    func testFormattedValueTextForNumberRangeUsesHyphen() {
        let text = ConditionChipDisplayUtils.displayValueText(for: makeCondition(
            propertyKey: "size",
            valueType: "number",
            values: ["10", "20"],
        ))

        XCTAssertEqual(text, "10 and 20")
    }
}

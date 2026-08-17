import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

enum ConditionChipDisplay {
    /// date picker 상태 캡슐화
    struct DatePickerState: Equatable {
        var presented: Bool
        var values: [String]
        var dateValueState: DateValueState?
    }

    static func displayValueText(for condition: Condition, displayValues: [String]? = nil) -> String {
        let values = displayValues ?? condition.values
        guard let values, !values.isEmpty else { return "Value" }

        if condition.property.type.rawValue == "date" || condition.property.type.rawValue == "datetime" {
            if values.count >= 2 {
                let first = absoluteDateText(values[0])
                let second = absoluteDateText(values[1])
                if first == second {
                    return first
                }
                return first + " ~ " + second
            }

            return displayDateValueText(values[0])
        }

        if values.count >= 2 {
            return values[0] + " and " + values[1]
        }
        return values[0]
    }

    static func placeholder(for arity: Int, index: Int, valueType: String) -> String {
        if arity >= 2 {
            return index == 0 ? "From" : "To"
        }

        switch valueType {
        case "number":
            return "Number Value"
        default:
            return "Value"
        }
    }

    static func displayedValuesForDate(
        conditionValues: [String]?,
        pickerState: DatePickerState,
    ) -> [String]? {
        if pickerState.presented {
            if let dateValueState = pickerState.dateValueState, pickerState.values.count <= 1 {
                return [dateValueState.displayText()]
            }
            if pickerState.values.count >= 2 {
                return pickerState.values.map(absoluteDateText)
            }
            return pickerState.values.map(displayDateValueText)
        }

        guard let conditionValues else { return nil }
        if conditionValues.count >= 2 {
            return conditionValues.map(absoluteDateText)
        }
        return conditionValues.map(displayDateValueText)
    }

    static func displayDateValueText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed == AppliedFilterValueUtils.recentsSinceAnyOpenedLiteral {
            return "Ever opened"
        }

        if let literal = RelativeDateConditionLiteral(canonicalLiteral: trimmed) {
            return literal.displayText()
        }

        guard let date = ConditionValueNormalizer.parseDate(trimmed) else {
            return trimmed
        }

        if DateNormalizerUtils.formatDateOnly(date) == DateNormalizerUtils.formatDateOnly(Date()) {
            return "Today"
        }

        return DateNormalizerUtils.formatDateOnly(date)
    }

    private static func absoluteDateText(_ value: String) -> String {
        ConditionValueNormalizer.formatDateOnlyString(value) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

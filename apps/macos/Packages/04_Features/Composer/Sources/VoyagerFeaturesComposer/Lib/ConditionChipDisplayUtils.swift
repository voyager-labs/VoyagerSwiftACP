import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

enum ConditionChipDisplayUtils {
    static func displayValueText(for condition: Condition, displayValues: [String]? = nil) -> String {
        let values = displayValues ?? condition.values
        guard let values, !values.isEmpty else { return "Value" }

        if condition.valueType == "date" || condition.valueType == "datetime" {
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
        conditionPropertyKey: String,
        pickerPropertyKey: String?,
        pickerPresented: Bool,
        pickerValues: [String],
        pickerDateValueState: DateValueState?,
    ) -> [String]? {
        if pickerPresented, pickerPropertyKey == conditionPropertyKey {
            if let pickerDateValueState, pickerValues.count <= 1 {
                return [pickerDateValueState.displayText()]
            }
            if pickerValues.count >= 2 {
                return pickerValues.map(absoluteDateText)
            }
            return pickerValues.map(displayDateValueText)
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

        guard let date = ValueNormalizerUtils.parseDate(trimmed) else {
            return trimmed
        }

        if DateNormalizerUtils.formatDateOnly(date) == DateNormalizerUtils.formatDateOnly(Date()) {
            return "Today"
        }

        return DateNormalizerUtils.formatDateOnly(date)
    }

    private static func absoluteDateText(_ value: String) -> String {
        ValueNormalizerUtils.formatDateOnlyString(value) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

enum ConditionChipDisplayUtils {
    static func displayValueText(for condition: Condition) -> String {
        guard let values = condition.values, !values.isEmpty else { return "Value" }
        let suffix = if condition.propertyKey == "size", condition.valueType == "number" {
            " bytes"
        } else {
            ""
        }

        if condition.valueType == "date" || condition.valueType == "datetime" {
            let first = ValueNormalizerUtils.formatDateOnlyString(values[0]) ?? values[0]
            if values.count >= 2 {
                let second = ValueNormalizerUtils.formatDateOnlyString(values[1]) ?? values[1]
                if first == second {
                    return first + suffix
                }
                return first + " ~ " + second + suffix
            }
            return first + suffix
        }

        if values.count >= 2 {
            return values[0] + " and " + values[1] + suffix
        }
        return values[0] + suffix
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
}

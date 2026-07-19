import Foundation

enum ConditionValueFieldPresentation {
    static func fieldTitle(for valueType: String, index: Int? = nil) -> String {
        let base = switch valueType {
        case "string":
            "Text"
        case "number":
            "Number"
        case "date", "datetime":
            "Date"
        case "boolean":
            "Boolean"
        case "string_list", "categorical":
            "List"
        default:
            "Value"
        }

        if let index {
            return index == 0 ? "\(base) (from)" : "\(base) (to)"
        }
        return base
    }

    static func fieldPlaceholder(for valueType: String) -> String {
        switch valueType {
        case "number":
            "Number Value"
        default:
            "Enter value"
        }
    }
}

import Foundation

enum AppliedFiltersUtils {
    static func resolve(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
    ) -> (scopes: [String], conditions: [Condition]) {
        let scopes = appliedFilters?.scopes ?? fallbackScopes
        let conditions: [Condition] = if let appliedConditions = appliedFilters?.conditions {
            appliedConditions.map(makeCondition(from:))
        } else {
            fallbackConditions
        }
        return (scopes, conditions)
    }

    private static func makeCondition(from payload: SearchConditionPayload) -> Condition {
        let propertyKey = payload.propertyKey
        let propertyLabel = ConditionMapping.defaultLabel(forKey: propertyKey)
        let propertyType = ConditionOperatorMapping.propertyTypeString(for: propertyKey)
        let operatorOption = ConditionOperatorMapping
            .operatorOptions(for: propertyKey)
            .first { $0.code == payload.operator }
        let valueUIKind = operatorOption?.valueUI ?? .singleText
        let operatorLabel = operatorOption?.label ?? payload.operator
        let valueType = operatorOption == nil
            ? valueType(for: propertyType)
            : valueType(for: valueUIKind)

        return Condition(
            propertyKey: propertyKey,
            propertyLabel: propertyLabel,
            propertyType: propertyType,
            operatorCode: payload.operator,
            operatorLabel: operatorLabel,
            operatorValueArity: ValueNormalizer.expectedArity(for: valueUIKind),
            valueType: valueType,
            values: stringValues(from: payload.value, valueUIKind: valueUIKind),
        )
    }

    private static func valueType(for propertyType: String) -> ValueType {
        switch propertyType {
        case "string":
            .string
        case "number":
            .number
        case "date", "datetime":
            .date
        case "boolean":
            .boolean
        case "array":
            .array
        default:
            .unknown
        }
    }

    private static func valueType(for valueUIKind: ValueUIKind) -> ValueType {
        switch valueUIKind {
        case .singleNumber, .rangeNumber, .listNumber:
            .number
        case .singleDate, .rangeDate:
            .date
        case .toggle:
            .boolean
        case .listText, .singleText, .none:
            .string
        }
    }

    private static func stringValues(from value: JSONValue?, valueUIKind: ValueUIKind) -> [String]? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            return [normalizeDateString(text, valueUIKind: valueUIKind) ?? text]
        case let .number(number):
            return [formatNumber(number)]
        case let .bool(flag):
            return [flag ? "true" : "false"]
        case let .array(values):
            let strings = values.compactMap { stringValue(from: $0, valueUIKind: valueUIKind) }
            return strings.isEmpty ? nil : strings
        case .object, .null:
            return nil
        }
    }

    private static func stringValue(from value: JSONValue, valueUIKind: ValueUIKind) -> String? {
        switch value {
        case let .string(text):
            normalizeDateString(text, valueUIKind: valueUIKind) ?? text
        case let .number(number):
            formatNumber(number)
        case let .bool(flag):
            flag ? "true" : "false"
        case .array, .object, .null:
            nil
        }
    }

    private static func normalizeDateString(_ text: String, valueUIKind: ValueUIKind) -> String? {
        switch valueUIKind {
        case .singleDate, .rangeDate:
            ValueNormalizer.formatDateOnlyString(text)
        default:
            nil
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

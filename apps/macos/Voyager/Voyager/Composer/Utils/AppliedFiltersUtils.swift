import Foundation

enum AppliedFiltersUtils {
    static func resolve(
        _ appliedFilters: AppliedFiltersPayload?,
        fallbackScopes: [String],
        fallbackConditions: [Condition],
        registryClient: RegistryClient,
    ) -> (scopes: [String], conditions: [Condition]) {
        let scopes = appliedFilters?.scopes ?? fallbackScopes
        let conditions: [Condition] =
            if let appliedConditions = appliedFilters?.conditions {
                appliedConditions.map { makeCondition(from: $0, registryClient: registryClient) }
            } else {
                fallbackConditions
            }
        return (scopes, conditions)
    }

    private static func makeCondition(
        from payload: SearchConditionPayload,
        registryClient: RegistryClient,
    ) -> Condition {
        let propertyKey = payload.propertyKey
        let propertyLabel = registryClient.label(for: propertyKey)
        let propertyType = registryClient.propertyTypeString(for: propertyKey)
        let typeKey = conditionTypeKey(for: propertyType)
        let operatorDefinition = registryClient.operatorDefinition(payload.operator)
        let valueUIKind = registryClient.operatorUIKind(for: payload.operator, typeKey: typeKey)
        let operatorLabel = operatorDefinition.uiLabel ?? payload.operator
        let valueType = registryClient.valueType(for: valueUIKind)

        return Condition(
            propertyKey: propertyKey,
            propertyLabel: propertyLabel,
            propertyType: propertyType,
            operatorCode: payload.operator,
            operatorLabel: operatorLabel,
            operatorValueArity: ValueNormalizerUtils.expectedArity(for: valueUIKind),
            operatorValueUIKind: valueUIKind,
            valueType: valueType,
            values: stringValues(from: payload.value, valueUIKind: valueUIKind),
        )
    }

    private static func stringValues(from value: JSONValue?, valueUIKind: String) -> [String]? {
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

    private static func stringValue(from value: JSONValue, valueUIKind: String) -> String? {
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

    private static func normalizeDateString(_ text: String, valueUIKind: String) -> String? {
        switch valueUIKind {
        case "singleDate", "rangeDate":
            ValueNormalizerUtils.formatDateOnlyString(text)
        default:
            nil
        }
    }

    private static func conditionTypeKey(for rawType: String) -> String {
        switch rawType.lowercased() {
        case "string":
            "string"
        case "number":
            "number"
        case "date", "datetime":
            "date"
        case "boolean":
            "boolean"
        case "string_list":
            "string_list"
        default:
            "unknown"
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

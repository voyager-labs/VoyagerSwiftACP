import VoyagerShared

enum ConditionValueEncoder {
    static func encode(condition: Condition, values: [String]) -> VoyagerShared.JSONValue? {
        encodeValues(
            values: values,
            valueType: condition.valueType,
            operatorCode: condition.operatorCode,
            operatorValueUIKind: condition.operatorValueUIKind,
        )
    }

    static func encodeValues(
        values: [String],
        valueType: String,
        operatorCode: String?,
        operatorValueUIKind: String?,
    ) -> VoyagerShared.JSONValue? {
        if let kind = operatorValueUIKind {
            if let listValue = encodeListValue(kind: kind, values: values) {
                return listValue
            }
        }

        return encodeValueByType(
            values: values,
            valueType: valueType,
            operatorCode: operatorCode,
        )
    }

    private static func encodeListValue(kind: String, values: [String]) -> VoyagerShared.JSONValue? {
        switch kind {
        case "listText":
            return .array(values.map(VoyagerShared.JSONValue.string))
        case "listNumber":
            let numbers = values.compactMap(Double.init)
            guard numbers.count == values.count else { return nil }
            return .array(numbers.map(VoyagerShared.JSONValue.number))
        default:
            return nil
        }
    }

    private static func encodeValueByType(
        values: [String],
        valueType: String,
        operatorCode: String?,
    ) -> VoyagerShared.JSONValue? {
        switch valueType {
        case "number":
            encodeNumberValues(values)

        case "boolean":
            encodeBooleanValue(values)

        case "date", "datetime":
            encodeDateValues(values)

        case "string_list", "categorical", "string", "unknown":
            encodeStringValues(values, operatorCode: operatorCode)

        default:
            encodeDefaultValues(values)
        }
    }

    private static func encodeNumberValues(_ values: [String]) -> VoyagerShared.JSONValue? {
        let numbers = values.compactMap(Double.init)
        guard numbers.count == values.count else { return nil }
        if numbers.count == 1 {
            return .number(numbers[0])
        }
        return .array(numbers.map(VoyagerShared.JSONValue.number))
    }

    private static func encodeBooleanValue(_ values: [String]) -> VoyagerShared.JSONValue? {
        guard let first = values.first?.lowercased() else { return nil }
        if first == "true" {
            return .bool(true)
        }
        if first == "false" {
            return .bool(false)
        }
        return nil
    }

    private static func encodeDateValues(_ values: [String]) -> VoyagerShared.JSONValue? {
        let formattedValues = values.map { value in
            ValueNormalizerUtils.formatDateOnlyString(value) ?? value
        }
        if formattedValues.count == 1 {
            return .string(formattedValues[0])
        }
        return .array(formattedValues.map(VoyagerShared.JSONValue.string))
    }

    private static func encodeStringValues(
        _ values: [String],
        operatorCode: String?,
    ) -> VoyagerShared.JSONValue? {
        let op = operatorCode?.lowercased()
        if op == "in" || op == "anyof" {
            return .array(values.map(VoyagerShared.JSONValue.string))
        }
        return encodeDefaultValues(values)
    }

    private static func encodeDefaultValues(_ values: [String]) -> VoyagerShared.JSONValue? {
        if values.count == 1 {
            return .string(values[0])
        }
        return .array(values.map(VoyagerShared.JSONValue.string))
    }
}

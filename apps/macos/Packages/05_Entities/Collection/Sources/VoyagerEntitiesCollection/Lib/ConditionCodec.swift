import VoyagerShared

public enum ConditionCodec {
    public static func encode(condition: Condition) -> JSONValue? {
        guard let operation = condition.operation,
              condition.isExecutionReady
        else {
            return nil
        }
        return encode(values: condition.values ?? [], contract: operation.valueContract)
    }

    static func decode(_ value: JSONValue?, contract: Condition.ValueContract) -> [String]? {
        switch contract.input {
        case .none: value == nil ? [] : nil
        case .singleText: decodedSingleText(value)
        case .listText: decodedTextArray(value)
        case .singleNumber: decodedSingleNumber(value)
        case .listNumber: decodedNumberArray(value, requiresValues: true)
        case .singleDate: decodedSingleDate(value)
        case .rangeDate: decodedDateArray(value)
        case .rangeNumber: decodedNumberArray(value, requiresValues: false)
        case .toggle: decodedToggle(value)
        }
    }

    private static func encode(values: [String], contract: Condition.ValueContract) -> JSONValue? {
        switch contract.input {
        case .none: nil
        case .singleText: values.count == 1 ? .string(values[0]) : nil
        case .listText: values.isEmpty ? nil : .array(values.map(JSONValue.string))
        case .singleNumber: encodedSingleNumber(values)
        case .listNumber: encodedNumberArray(values, count: nil)
        case .singleDate: encodedSingleDate(values)
        case .rangeDate: encodedDateArray(values)
        case .rangeNumber: encodedNumberArray(values, count: 2)
        case .toggle: encodedToggle(values)
        }
    }

    private static func decodedSingleText(_ value: JSONValue?) -> [String]? {
        guard case let .string(text) = value else { return nil }
        return [text]
    }

    private static func decodedTextArray(_ value: JSONValue?) -> [String]? {
        guard case let .array(values) = value else { return nil }
        let texts = values.compactMap { if case let .string(text) = $0 { text } else { nil } }
        return texts.count == values.count && !texts.isEmpty ? texts : nil
    }

    private static func decodedSingleNumber(_ value: JSONValue?) -> [String]? {
        guard case let .number(number) = value else { return nil }
        return [String(number)]
    }

    private static func decodedNumberArray(_ value: JSONValue?, requiresValues: Bool) -> [String]? {
        guard case let .array(values) = value else { return nil }
        let numbers = values.compactMap { if case let .number(number) = $0 { String(number) } else { nil } }
        return numbers.count == values.count && (!requiresValues || !numbers.isEmpty) ? numbers : nil
    }

    private static func decodedSingleDate(_ value: JSONValue?) -> [String]? {
        guard case let .string(text) = value,
              let normalized = ConditionValueNormalizer.canonicalSingleDateString(text)
        else { return nil }
        return [normalized]
    }

    private static func decodedDateArray(_ value: JSONValue?) -> [String]? {
        guard case let .array(values) = value else { return nil }
        let dates = values
            .compactMap {
                if case let .string(text) = $0 {
                    ConditionValueNormalizer.canonicalAbsoluteDateString(text)
                } else {
                    nil
                }
            }
        return dates.count == values.count ? dates : nil
    }

    private static func decodedToggle(_ value: JSONValue?) -> [String]? {
        guard case let .bool(flag) = value else { return nil }
        return [flag ? "true" : "false"]
    }

    private static func encodedSingleNumber(_ values: [String]) -> JSONValue? {
        guard values.count == 1, let number = Double(values[0]) else { return nil }
        return .number(number)
    }

    private static func encodedNumberArray(_ values: [String], count: Int?) -> JSONValue? {
        let numbers = values.compactMap(Double.init)
        guard numbers.count == values.count, !numbers.isEmpty,
              count == nil || numbers.count == count else { return nil }
        return .array(numbers.map(JSONValue.number))
    }

    private static func encodedSingleDate(_ values: [String]) -> JSONValue? {
        guard values.count == 1,
              let date = ConditionValueNormalizer.canonicalSingleDateString(values[0]) else { return nil }
        return .string(date)
    }

    private static func encodedDateArray(_ values: [String]) -> JSONValue? {
        let dates = values.compactMap(ConditionValueNormalizer.canonicalAbsoluteDateString)
        return dates.count == values.count && dates.count == 2 ? .array(dates.map(JSONValue.string)) : nil
    }

    private static func encodedToggle(_ values: [String]) -> JSONValue? {
        guard values.count == 1 else { return nil }
        switch values[0].lowercased() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: return nil
        }
    }
}

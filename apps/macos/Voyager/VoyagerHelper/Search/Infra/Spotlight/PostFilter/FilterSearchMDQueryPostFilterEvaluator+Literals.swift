import Foundation

extension FilterSearchMDQueryPostFilterEvaluator {
    func isPresent(_ value: Any?, typeKey: String) -> Bool {
        switch typeKey {
        case "string", "categorical":
            normalizedString(value) != nil
        case "string_list":
            normalizedStringList(value).isEmpty == false
        case "number":
            normalizedNumber(value) != nil
        case "date":
            normalizedDate(value) != nil
        case "boolean":
            normalizedBoolean(value) != nil
        default:
            value != nil
        }
    }

    func isEmpty(_ value: Any?, typeKey: String) -> Bool {
        switch typeKey {
        case "string", "categorical":
            guard let stringValue = normalizedString(value) else {
                return true
            }
            return stringValue.isEmpty
        case "string_list":
            return normalizedStringList(value).isEmpty
        default:
            return value == nil
        }
    }

    func normalizedString(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let asDouble = number.doubleValue
            if asDouble.rounded() == asDouble {
                return String(Int64(asDouble))
            }
            return String(asDouble)
        }
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let url = value as? URL {
            return url.path
        }
        if let array = value as? [Any],
           let first = array.first
        {
            return normalizedString(first)
        }
        return String(describing: value)
    }

    func normalizedStringList(_ value: Any?) -> [String] {
        guard let value else {
            return []
        }
        if let array = value as? [Any] {
            return array.compactMap { normalizedString($0) }.filter { $0.isEmpty == false }
        }
        if let set = value as? Set<AnyHashable> {
            return set.compactMap { normalizedString($0.base) }.filter { $0.isEmpty == false }
        }
        if let string = normalizedString(value) {
            return string.isEmpty ? [] : [string]
        }
        return []
    }

    func normalizedNumber(_ value: Any?) -> Double? {
        guard let value else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func normalizedDate(_ value: Any?) -> Date? {
        guard let value else {
            return nil
        }
        if let date = value as? Date {
            return date
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = value as? String {
            return parseDateLiteral(string)
        }
        return nil
    }

    func normalizedBoolean(_ value: Any?) -> Bool? {
        guard let value else {
            return nil
        }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                return true
            }
            if ["false", "0", "no"].contains(normalized) {
                return false
            }
        }
        return nil
    }

    func readString(_ condition: SearchConditionPayload) throws -> String {
        guard case let .string(value)? = condition.value,
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
        return value
    }

    func readStringList(_ condition: SearchConditionPayload) throws -> [String] {
        let values: [JSONValue]
        if case let .array(items)? = condition.value {
            values = items
        } else if let value = condition.value {
            values = [value]
        } else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let normalized = values.compactMap { item -> String? in
            switch item {
            case let .string(text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case let .number(number):
                if number.rounded() == number {
                    return String(Int64(number))
                }
                return String(number)
            case let .bool(flag):
                return flag ? "true" : "false"
            default:
                return nil
            }
        }

        guard normalized.isEmpty == false else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
        return normalized
    }

    func readNumber(_ condition: SearchConditionPayload) throws -> Double {
        switch condition.value {
        case let .number(number)?:
            return number
        case let .string(text)?:
            if let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        default:
            break
        }

        throw EvaluationError.invalidValue(
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
    }

    func readNumberRange(_ condition: SearchConditionPayload) throws -> (Double, Double) {
        guard case let .array(values)? = condition.value,
              values.count == 2
        else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let lower = try readNumber(
            SearchConditionPayload(propertyKey: condition.propertyKey, operator: condition.operator, value: values[0]),
        )
        let upper = try readNumber(
            SearchConditionPayload(propertyKey: condition.propertyKey, operator: condition.operator, value: values[1]),
        )
        return (min(lower, upper), max(lower, upper))
    }

    func readDate(_ condition: SearchConditionPayload) throws -> Date {
        let literal: String
        switch condition.value {
        case let .string(text)?:
            literal = text
        case let .number(number)?:
            return Date(timeIntervalSince1970: number)
        default:
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        guard let parsed = parseDateLiteral(literal) else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
        return parsed
    }

    func readDateRange(_ condition: SearchConditionPayload) throws -> (Date, Date) {
        guard case let .array(values)? = condition.value,
              values.count == 2
        else {
            throw EvaluationError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let first = try readDate(
            SearchConditionPayload(propertyKey: condition.propertyKey, operator: condition.operator, value: values[0]),
        )
        let second = try readDate(
            SearchConditionPayload(propertyKey: condition.propertyKey, operator: condition.operator, value: values[1]),
        )
        return first <= second ? (first, second) : (second, first)
    }

    func readBool(_ condition: SearchConditionPayload) throws -> Bool {
        switch condition.value {
        case let .bool(flag)?:
            return flag
        case let .string(text)?:
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                return true
            }
            if ["false", "0", "no"].contains(normalized) {
                return false
            }
        default:
            break
        }

        throw EvaluationError.invalidValue(
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
    }

    func parseDateLiteral(_ literal: String) -> Date? {
        var text = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$time.iso("), text.hasSuffix(")") {
            text = String(text.dropFirst(10).dropLast())
        }

        if text.count == 10, text[text.index(text.startIndex, offsetBy: 4)] == "-", text[text.index(
            text.startIndex,
            offsetBy: 7,
        )] == "-" {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: text) {
            return date
        }
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: text) {
            return date
        }
        return nil
    }

    func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    func contains(_ lhs: String, _ rhs: String) -> Bool {
        lhs.range(of: rhs, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    func containsAny(_ lhs: [String], _ rhs: [String]) -> Bool {
        let lhsSet = Set(lhs.map(normalizeToken))
        let rhsSet = Set(rhs.map(normalizeToken))
        return lhsSet.isDisjoint(with: rhsSet) == false
    }

    func containsAll(_ lhs: [String], _ rhs: [String]) -> Bool {
        let lhsSet = Set(lhs.map(normalizeToken))
        let rhsSet = Set(rhs.map(normalizeToken))
        return rhsSet.isSubset(of: lhsSet)
    }

    func normalizeToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current,
        )
    }

    func wildcardMatch(_ candidate: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: candidate.utf16.count)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }
}

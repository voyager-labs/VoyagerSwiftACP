import Foundation
import VoyagerShared

extension SpotlightQueryCompiler {
    func readString(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> String {
        guard case let .string(text)? = value,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        return text
    }

    func readStringList(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> [String] {
        let values: [JSONValue]
        if case let .array(items)? = value {
            values = items
        } else if let value {
            values = [value]
        } else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }

        let normalized = values.compactMap { entry -> String? in
            switch entry {
            case let .string(text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case let .number(number):
                return formatNumber(number)
            case let .bool(flag):
                return flag ? "true" : "false"
            default:
                return nil
            }
        }
        guard normalized.isEmpty == false else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        return normalized
    }

    func readNumber(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> Double {
        switch value {
        case let .number(number)?:
            return number
        case let .string(text)?:
            if let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        default:
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
    }

    func readNumberRange(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> (Double, Double) {
        guard case let .array(values)? = value,
              values.count == 2
        else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        let first = try readNumber(values[0], propertyKey: propertyKey, operatorCode: operatorCode)
        let second = try readNumber(values[1], propertyKey: propertyKey, operatorCode: operatorCode)
        return (min(first, second), max(first, second))
    }

    func readNumberList(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> [Double] {
        guard case let .array(values)? = value, values.isEmpty == false else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        return try values.map {
            try readNumber($0, propertyKey: propertyKey, operatorCode: operatorCode)
        }
    }

    func readDateLiteral(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> String {
        switch value {
        case let .string(text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
            }
            return trimmed
        case let .number(number)?:
            return formatNumber(number)
        default:
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
    }

    func readDateRange(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> (String, String) {
        guard case let .array(values)? = value,
              values.count == 2
        else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }

        let first = try readDateLiteral(values[0], propertyKey: propertyKey, operatorCode: operatorCode)
        let second = try readDateLiteral(values[1], propertyKey: propertyKey, operatorCode: operatorCode)
        if first <= second {
            return (first, second)
        }
        return (second, first)
    }

    func readBoolean(
        _ value: JSONValue?,
        propertyKey: String,
        operatorCode: String,
    ) throws -> Bool {
        switch value {
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
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        default:
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
    }

    func escapeLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func normalizeWildcardPattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\.\\*", with: "*")
            .replacingOccurrences(of: ".*", with: "*")
            .replacingOccurrences(of: "%", with: "*")
    }

    func token(for value: String, propertyKey: String) -> String {
        if propertyKey == "extension" {
            let trimmed = value.hasPrefix(".") ? String(value.dropFirst()) : value
            return "*.\(trimmed)"
        }
        return value
    }

    func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int64(value))
        }
        return String(value)
    }
}

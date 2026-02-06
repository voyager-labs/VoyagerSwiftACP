import Foundation

extension FilterSearchConditionBuilder {
    func validateOperatorMeta(_ operatorMeta: OperatorDefinition, operatorCode: String) throws {
        guard let sqlKind = operatorMeta.sqlKind else {
            throw BuilderError(message: "Missing sql_kind for operator '\(operatorCode)'")
        }
        guard let valueShape = operatorMeta.valueShape else { return }
        if let allowedShapes = kSqlKindValueShapes[sqlKind], !allowedShapes.contains(valueShape) {
            throw BuilderError(
                message: "Operator '\(operatorCode)' value_shape mismatch: '\(valueShape)' for sql_kind '\(sqlKind)'",
            )
        }
    }

    func validateValue(
        _ valueCount: ValueCount?,
        operatorCode: String,
        value: JSONValue?,
        propertyKey: String,
    ) throws {
        guard let valueCount else {
            return
        }
        switch valueCount {
        case .fixed(0):
            try validateNoValue(operatorCode: operatorCode, value: value, propertyKey: propertyKey)
        case .fixed(1):
            try validateSingleValue(operatorCode: operatorCode, value: value, propertyKey: propertyKey)
        case .fixed(2):
            try validateRangeValue(operatorCode: operatorCode, value: value, propertyKey: propertyKey)
        case .multiple:
            try validateMultipleValue(operatorCode: operatorCode, value: value, propertyKey: propertyKey)
        default:
            break
        }
    }

    func jsonPath(for systemKeys: [String]) -> String? {
        guard !systemKeys.isEmpty else { return nil }
        var preferred: String?
        for key in systemKeys where key.hasPrefix("mditem:") {
            preferred = key
            break
        }
        if preferred == nil {
            for key in systemKeys where !key.hasPrefix("nsurl:") {
                preferred = key
                break
            }
        }
        if preferred == nil {
            preferred = systemKeys.first
        }
        guard let target = preferred else { return nil }
        if let colonIndex = target.firstIndex(of: ":") {
            let suffix = target[target.index(after: colonIndex)...]
            return "$.\(suffix)"
        }
        return "$.\(target)"
    }

    func conditionTypeKey(for rawType: String) -> String? {
        switch rawType.lowercased() {
        case "string": "string"
        case "categorical": "categorical"
        case "number": "number"
        case "date", "datetime": "date"
        case "boolean": "boolean"
        case "string_list": "string_list"
        default: nil
        }
    }

    static func buildPropertyMap(systemRegistry: SystemPropertyRegistry) -> [String: PropertyMapping] {
        var map: [String: PropertyMapping] = [:]
        for (_, entries) in systemRegistry.categories {
            for (key, definition) in entries {
                map[key] = PropertyMapping(
                    key: key,
                    type: definition.type,
                    systemKeys: definition.systemKeys,
                    dbIndexed: definition.dbIndexed ?? false,
                    uiHidden: definition.uiHidden ?? false,
                )
            }
        }
        return map
    }

    private func validateNoValue(
        operatorCode: String,
        value: JSONValue?,
        propertyKey: String,
    ) throws {
        if value != nil {
            throw BuilderError(message: "Operator '\(operatorCode)' does not accept a value for '\(propertyKey)'")
        }
    }

    private func validateSingleValue(
        operatorCode: String,
        value: JSONValue?,
        propertyKey: String,
    ) throws {
        if value == nil {
            throw BuilderError(message: "Operator '\(operatorCode)' requires a value for '\(propertyKey)'")
        }
    }

    private func validateRangeValue(
        operatorCode: String,
        value: JSONValue?,
        propertyKey: String,
    ) throws {
        guard case let .array(values)? = value, values.count == 2 else {
            throw BuilderError(message: "Operator '\(operatorCode)' requires [min, max] for '\(propertyKey)'")
        }
    }

    private func validateMultipleValue(
        operatorCode: String,
        value: JSONValue?,
        propertyKey: String,
    ) throws {
        guard let value else {
            throw BuilderError(message: "Operator '\(operatorCode)' requires non-empty value for '\(propertyKey)'")
        }
        if case let .array(values) = value, values.isEmpty {
            throw BuilderError(message: "Operator '\(operatorCode)' requires non-empty array for '\(propertyKey)'")
        }
    }
}

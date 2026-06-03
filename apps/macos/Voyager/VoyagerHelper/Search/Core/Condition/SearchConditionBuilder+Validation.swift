import Foundation
import VoyagerShared

extension SearchConditionBuilder {
    func canonicalVisiblePropertyKey(for rawKey: String) -> String? {
        if let mapping = propertyMap[rawKey], mapping.uiHidden == false {
            return rawKey
        }
        guard let canonicalKey = legacyKeyMap[rawKey],
              let mapping = propertyMap[canonicalKey],
              mapping.uiHidden == false
        else {
            return nil
        }
        return canonicalKey
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
                    uiHidden: definition.uiHidden ?? false,
                )
            }
        }
        return map
    }

    static func buildLegacyKeyMap(systemRegistry: SystemPropertyRegistry) -> [String: String] {
        var map: [String: String] = [:]
        for (_, entries) in systemRegistry.categories {
            for (canonicalKey, definition) in entries {
                guard let legacyKeys = definition.legacyKeys else {
                    continue
                }
                for legacyKey in legacyKeys where map[legacyKey] == nil {
                    map[legacyKey] = canonicalKey
                }
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

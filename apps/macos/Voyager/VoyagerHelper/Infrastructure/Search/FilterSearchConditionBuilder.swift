import Foundation
@preconcurrency import GRDB

struct FilterSearchConditionBuilder: Sendable {
    struct BuilderError: Error, CustomStringConvertible {
        let message: String

        var description: String { message }
    }

    struct ParamBinder {
        private(set) var arguments: [String: DatabaseValueConvertible?] = [:]
        private var index = 0
        private let prefix: String

        init(prefix: String = "p") {
            self.prefix = prefix
        }

        mutating func bind(_ value: DatabaseValueConvertible?) -> String {
            let name = "\(prefix)\(index)"
            index += 1
            arguments[name] = value
            return ":\(name)"
        }

        mutating func bindMany(_ values: [DatabaseValueConvertible?]) -> String {
            values.map { bind($0) }.joined(separator: ", ")
        }
    }

    struct PropertyMapping: Sendable {
        let key: String
        let type: String
        let systemKeys: [String]
        let dbIndexed: Bool
        let uiHidden: Bool
    }

    let registry: PropertyConditionRegistry
    let propertyMap: [String: PropertyMapping]

    init(bundle: Bundle = .main) throws {
        registry = try RegistryLoader.load(resourceName: "property_condition_registry", bundle: bundle)
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        propertyMap = FilterSearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
    }

    func buildWhere(conditions: [SearchConditionPayload]) throws -> (String, [String: DatabaseValueConvertible?]) {
        guard !conditions.isEmpty else {
            return ("1=1", [:])
        }

        var clauses: [String] = []
        var binder = ParamBinder()

        for condition in conditions {
            guard let clause = try buildClause(
                condition: condition,
                binder: &binder,
            ) else {
                continue
            }
            clauses.append(clause)
        }

        guard !clauses.isEmpty else {
            return ("1=1", [:])
        }

        return (clauses.joined(separator: " AND "), binder.arguments)
    }

    func buildClause(
        condition: SearchConditionPayload,
        binder: inout ParamBinder,
    ) throws -> String? {
        let propertyKey = condition.propertyKey
        let operatorCode = condition.operator
        let value = condition.value

        guard let mapping = propertyMap[propertyKey] else {
            throw BuilderError(message: "Unknown propertyKey: \(propertyKey)")
        }
        if mapping.uiHidden {
            throw BuilderError(message: "Hidden propertyKey: \(propertyKey)")
        }

        guard let typeKey = conditionTypeKey(for: mapping.type) else {
            throw BuilderError(message: "Unsupported property type: \(mapping.type)")
        }
        guard let propertyType = registry.propertyTypes[typeKey] else {
            throw BuilderError(message: "Missing property_types for \(typeKey)")
        }
        guard propertyType.operators.contains(operatorCode) else {
            throw BuilderError(message: "Operator '\(operatorCode)' not supported for '\(propertyKey)'")
        }

        guard let operatorMeta = registry.operators[operatorCode] else {
            throw BuilderError(message: "Unknown operator: \(operatorCode)")
        }
        try validateOperatorMeta(operatorMeta, operatorCode: operatorCode)
        try validateValue(operatorMeta.valueCount, operatorCode: operatorCode, value: value, propertyKey: propertyKey)

        if mapping.dbIndexed {
            return try buildDbClause(
                mapping: mapping,
                operatorMeta: operatorMeta,
                operatorCode: operatorCode,
                value: value,
                binder: &binder,
            )
        }
        return try buildJsonClause(
            mapping: mapping,
            operatorMeta: operatorMeta,
            operatorCode: operatorCode,
            value: value,
            binder: &binder,
        )
    }
}

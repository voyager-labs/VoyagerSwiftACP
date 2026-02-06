import Foundation
import StructuredQueries

struct FilterSearchConditionBuilder: Sendable {
    struct BuilderError: Error, CustomStringConvertible {
        let message: String

        var description: String { message }
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

    init(registry: PropertyConditionRegistry, systemRegistry: SystemPropertyRegistry) {
        self.registry = registry
        propertyMap = FilterSearchConditionBuilder.buildPropertyMap(systemRegistry: systemRegistry)
    }

    func buildWhere(conditions: [SearchConditionPayload]) throws -> QueryFragment {
        guard !conditions.isEmpty else {
            return .alwaysTrue
        }

        var clauses: [QueryFragment] = []

        for condition in conditions {
            guard let clause = try buildClause(condition: condition) else {
                continue
            }
            clauses.append(clause)
        }

        guard !clauses.isEmpty else {
            return .alwaysTrue
        }

        return clauses.joinedWithAnd()
    }

    func buildClause(condition: SearchConditionPayload) throws -> QueryFragment? {
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
            )
        }
        return try buildJsonClause(
            mapping: mapping,
            operatorMeta: operatorMeta,
            operatorCode: operatorCode,
            value: value,
        )
    }
}

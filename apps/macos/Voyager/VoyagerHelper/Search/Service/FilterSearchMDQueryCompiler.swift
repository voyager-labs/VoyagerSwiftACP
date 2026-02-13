import Foundation
import Logging

private final class FilterSearchMDQueryCompilerBundleToken {}

struct FilterSearchMDQueryCompiler: Sendable {
    static let basePredicate = "kMDItemContentTypeTree == \"public.item\""

    enum CompileError: Error, LocalizedError {
        case unknownPropertyKey(String)
        case hiddenPropertyKey(String)
        case unsupportedPropertyType(String)
        case unsupportedOperator(propertyKey: String, operatorCode: String)
        case missingMDItemAttribute(String)
        case invalidValue(propertyKey: String, operatorCode: String)

        var errorDescription: String? {
            switch self {
            case let .unknownPropertyKey(propertyKey):
                "Unknown property key: \(propertyKey)"
            case let .hiddenPropertyKey(propertyKey):
                "Hidden property key is not supported: \(propertyKey)"
            case let .unsupportedPropertyType(propertyType):
                "Unsupported property type: \(propertyType)"
            case let .unsupportedOperator(propertyKey, operatorCode):
                "Operator '\(operatorCode)' is not supported for '\(propertyKey)'"
            case let .missingMDItemAttribute(propertyKey):
                "No mditem attribute mapping for property '\(propertyKey)'"
            case let .invalidValue(propertyKey, operatorCode):
                "Invalid value for '\(propertyKey)' with operator '\(operatorCode)'"
            }
        }
    }

    private let logger: Logger
    private let conditionBuilder: FilterSearchConditionBuilder

    init(
        bundle: Bundle,
        logger: Logger = Logger(label: "VoyagerHelper.FilterSearchMDQueryCompiler"),
    ) throws {
        self.logger = logger
        let conditionRegistry: PropertyConditionRegistry = try RegistryLoader.load(
            resourceName: "property_condition_registry",
            bundle: bundle,
        )
        let systemRegistry: SystemPropertyRegistry = try RegistryLoader.load(
            resourceName: "system_property_registry",
            bundle: bundle,
        )
        conditionBuilder = FilterSearchConditionBuilder(
            registry: conditionRegistry,
            systemRegistry: systemRegistry,
        )
    }

    init(
        logger: Logger = Logger(label: "VoyagerHelper.FilterSearchMDQueryCompiler"),
    ) throws {
        try self.init(bundle: Bundle(for: FilterSearchMDQueryCompilerBundleToken.self), logger: logger)
    }

    init(
        conditionBuilder: FilterSearchConditionBuilder,
        logger: Logger = Logger(label: "VoyagerHelper.FilterSearchMDQueryCompiler"),
    ) {
        self.logger = logger
        self.conditionBuilder = conditionBuilder
    }

    func compile(conditions: [SearchConditionPayload]) throws -> String {
        guard conditions.isEmpty == false else {
            return Self.basePredicate
        }

        var clauses: [String] = [Self.basePredicate]
        clauses.reserveCapacity(conditions.count + 1)
        for condition in conditions {
            try clauses.append(compileCondition(condition))
        }
        return clauses.joined(separator: " && ")
    }
}

extension FilterSearchMDQueryCompiler {
    private func compileCondition(_ condition: SearchConditionPayload) throws -> String {
        guard let mapping = conditionBuilder.propertyMap[condition.propertyKey] else {
            throw CompileError.unknownPropertyKey(condition.propertyKey)
        }
        if mapping.uiHidden {
            throw CompileError.hiddenPropertyKey(condition.propertyKey)
        }

        guard let typeKey = conditionBuilder.conditionTypeKey(for: mapping.type),
              let propertyType = conditionBuilder.registry.propertyTypes[typeKey]
        else {
            throw CompileError.unsupportedPropertyType(mapping.type)
        }

        guard propertyType.operators.contains(condition.operator),
              let operatorMeta = conditionBuilder.registry.operators[condition.operator]
        else {
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        if let allowedTypes = operatorMeta.allowedTypes,
           allowedTypes.contains(typeKey) == false
        {
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        do {
            try conditionBuilder.validateValue(
                operatorMeta.valueCount,
                operatorCode: condition.operator,
                value: condition.value,
                propertyKey: condition.propertyKey,
            )
        } catch {
            throw CompileError.invalidValue(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let attribute = try resolveAttributeName(mapping: mapping, propertyKey: condition.propertyKey)
        return try buildClause(attribute: attribute, typeKey: typeKey, condition: condition)
    }

    private func resolveAttributeName(
        mapping: FilterSearchConditionBuilder.PropertyMapping,
        propertyKey: String,
    ) throws -> String {
        if propertyKey == "extension" || propertyKey == "name_stem" {
            return "kMDItemFSName"
        }

        if let jsonPath = conditionBuilder.jsonPath(for: mapping.systemKeys),
           jsonPath.hasPrefix("$."),
           jsonPath.count > 2
        {
            return String(jsonPath.dropFirst(2))
        }

        throw CompileError.missingMDItemAttribute(propertyKey)
    }

    private func buildClause(
        attribute: String,
        typeKey: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        let operatorCode = condition.operator

        if operatorCode == "exists" {
            return "\(attribute) != nil"
        }
        if operatorCode == "empty" {
            return "(\(attribute) == nil || \(attribute) == \"\")"
        }

        switch typeKey {
        case "string":
            return try buildStringClause(attribute: attribute, condition: condition)
        case "categorical":
            return try buildCategoricalClause(attribute: attribute, condition: condition)
        case "string_list":
            return try buildStringListClause(attribute: attribute, condition: condition)
        case "number":
            return try buildNumberClause(attribute: attribute, condition: condition)
        case "date":
            return try buildDateClause(attribute: attribute, condition: condition)
        case "boolean":
            return try buildBooleanClause(attribute: attribute, condition: condition)
        default:
            throw CompileError.unsupportedPropertyType(typeKey)
        }
    }

    private func buildStringClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        let value = try readString(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let escaped = escapeLiteral(value)

        let eqClause: String
        if condition.propertyKey == "name_stem" {
            let exact = "\(attribute) ==[cd] \"\(escaped)\""
            let withExtension = "\(attribute) ==[cd] \"\(escaped).*\""
            eqClause = "(\(exact) || \(withExtension))"
        } else {
            eqClause = "\(attribute) ==[cd] \"\(escaped)\""
        }

        switch condition.operator {
        case "eq":
            return eqClause
        case "neq":
            return "NOT (\(eqClause))"
        case "cn":
            return "\(attribute) ==[cd] \"*\(escaped)*\""
        case "nc":
            return "NOT (\(attribute) ==[cd] \"*\(escaped)*\")"
        case "sw":
            return "\(attribute) ==[cd] \"\(escaped)*\""
        case "ew":
            return "\(attribute) ==[cd] \"*\(escaped)\""
        case "rx":
            return "\(attribute) ==[cd] \"\(normalizeWildcardPattern(escaped))\""
        default:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func buildCategoricalClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        switch condition.operator {
        case "any", "none":
            let values = try readStringList(
                condition.value,
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
            let comparisons = values
                .map { token(for: $0, propertyKey: condition.propertyKey) }
                .map { "\(attribute) ==[cd] \"\(escapeLiteral($0))\"" }
            let grouped = "(" + comparisons.joined(separator: " || ") + ")"
            if condition.operator == "none" {
                return "NOT \(grouped)"
            }
            return grouped
        case "eq", "neq", "cn", "nc", "sw", "ew", "rx":
            return try buildStringClause(attribute: attribute, condition: condition)
        default:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func buildStringListClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        let values = try readStringList(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let comparisons = values
            .map { token(for: $0, propertyKey: condition.propertyKey) }
            .map { "\(attribute) ==[cd] \"\(escapeLiteral($0))\"" }

        switch condition.operator {
        case "any":
            return "(" + comparisons.joined(separator: " || ") + ")"
        case "none":
            return "NOT (" + comparisons.joined(separator: " || ") + ")"
        case "all":
            return "(" + comparisons.joined(separator: " && ") + ")"
        case "miss":
            return "NOT (" + comparisons.joined(separator: " && ") + ")"
        default:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func buildNumberClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        switch condition.operator {
        case "btw", "nbtw":
            let (lower, upper) = try readNumberRange(
                condition.value,
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
            let between = "(\(attribute) >= \(formatNumber(lower)) && \(attribute) <= \(formatNumber(upper)))"
            if condition.operator == "nbtw" {
                return "NOT \(between)"
            }
            return between
        default:
            let number = try readNumber(
                condition.value,
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
            let rhs = formatNumber(number)
            switch condition.operator {
            case "eq":
                return "\(attribute) == \(rhs)"
            case "neq":
                return "\(attribute) != \(rhs)"
            case "gt":
                return "\(attribute) > \(rhs)"
            case "gte":
                return "\(attribute) >= \(rhs)"
            case "lt":
                return "\(attribute) < \(rhs)"
            case "lte":
                return "\(attribute) <= \(rhs)"
            default:
                throw CompileError.unsupportedOperator(
                    propertyKey: condition.propertyKey,
                    operatorCode: condition.operator,
                )
            }
        }
    }

    private func buildDateClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        switch condition.operator {
        case "btw", "nbtw":
            let (start, end) = try readDateRange(
                condition.value,
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
            let between = "(\(attribute) >= \"\(escapeLiteral(start))\" && \(attribute) <= \"\(escapeLiteral(end))\")"
            if condition.operator == "nbtw" {
                return "NOT \(between)"
            }
            return between
        default:
            let literal = try readDateLiteral(
                condition.value,
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
            let rhs = "\"\(escapeLiteral(literal))\""
            switch condition.operator {
            case "eq":
                return "\(attribute) == \(rhs)"
            case "neq":
                return "\(attribute) != \(rhs)"
            case "gt":
                return "\(attribute) > \(rhs)"
            case "gte":
                return "\(attribute) >= \(rhs)"
            case "lt":
                return "\(attribute) < \(rhs)"
            case "lte":
                return "\(attribute) <= \(rhs)"
            default:
                throw CompileError.unsupportedOperator(
                    propertyKey: condition.propertyKey,
                    operatorCode: condition.operator,
                )
            }
        }
    }

    private func buildBooleanClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        guard condition.operator == "eq" else {
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }

        let boolValue = try readBoolean(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        return "\(attribute) == \(boolValue ? "TRUE" : "FALSE")"
    }
}

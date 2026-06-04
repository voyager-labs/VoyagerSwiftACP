import Foundation
import Logging
import VoyagerShared

private final class SpotlightQueryCompilerBundleToken {}

struct SpotlightQueryCompiler {
    private let logger: Logger
    private let conditionBuilder: SearchConditionBuilder

    struct CompilePlan {
        let predicate: String
        let pushdownConditions: [SearchConditionPayload]
    }

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

    init(
        bundle: Bundle,
        logger: Logger = Logger(label: "VoyagerHelper.SpotlightQueryCompiler"),
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
        conditionBuilder = SearchConditionBuilder(
            registry: conditionRegistry,
            systemRegistry: systemRegistry,
        )
    }

    init(
        logger: Logger = Logger(label: "VoyagerHelper.SpotlightQueryCompiler"),
    ) throws {
        try self.init(bundle: Bundle(for: SpotlightQueryCompilerBundleToken.self), logger: logger)
    }

    init(
        conditionBuilder: SearchConditionBuilder,
        logger: Logger = Logger(label: "VoyagerHelper.SpotlightQueryCompiler"),
    ) {
        self.logger = logger
        self.conditionBuilder = conditionBuilder
    }

    func compile(conditions: [SearchConditionPayload]) throws -> String {
        try compilePlan(conditions: conditions).predicate
    }

    func compilePlan(conditions: [SearchConditionPayload]) throws -> CompilePlan {
        guard conditions.isEmpty == false else {
            return CompilePlan(
                predicate: Self.basePredicate,
                pushdownConditions: [],
            )
        }

        var clauses: [String] = [Self.basePredicate]
        clauses.reserveCapacity(conditions.count + 1)
        var pushdownConditions: [SearchConditionPayload] = []
        pushdownConditions.reserveCapacity(conditions.count)

        for condition in conditions {
            let validated = try validateCondition(condition)

            guard let attribute = resolveAttributeName(
                mapping: validated.mapping,
            ) else {
                throw CompileError.missingMDItemAttribute(condition.propertyKey)
            }

            let clause = try buildClause(
                attribute: attribute,
                typeKey: validated.typeKey,
                dateMdqueryOperator: validated.dateMdqueryOperator,
                condition: condition,
            )
            clauses.append(clause)
            pushdownConditions.append(condition)
        }

        return CompilePlan(
            predicate: clauses.joined(separator: " && "),
            pushdownConditions: pushdownConditions,
        )
    }

    static let basePredicate = "kMDItemContentTypeTree == \"public.item\""
}

extension SpotlightQueryCompiler {
    enum DateMdqueryOperator: String {
        case eq = "=="
        case neq = "!="
        case gt = ">"
        case gte = ">="
        case lt = "<"
        case lte = "<="
        case range = "RANGE"
        case notRange = "NOT_RANGE"
        case today = "TODAY"
    }

    private struct ValidatedCondition {
        let mapping: SearchConditionBuilder.PropertyMapping
        let typeKey: String
        let dateMdqueryOperator: DateMdqueryOperator?
    }

    private func validateCondition(_ condition: SearchConditionPayload) throws -> ValidatedCondition {
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

        let dateMdqueryOperator = try resolveDateMdqueryOperator(
            typeKey: typeKey,
            operatorMeta: operatorMeta,
            condition: condition,
        )

        return ValidatedCondition(
            mapping: mapping,
            typeKey: typeKey,
            dateMdqueryOperator: dateMdqueryOperator,
        )
    }

    private func resolveDateMdqueryOperator(
        typeKey: String,
        operatorMeta: OperatorDefinition,
        condition: SearchConditionPayload,
    ) throws -> DateMdqueryOperator? {
        guard typeKey == "date" else {
            return nil
        }
        guard let rawOperator = operatorMeta.mdqueryOperator,
              let parsedOperator = DateMdqueryOperator(rawValue: rawOperator)
        else {
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
        return parsedOperator
    }

    private func resolveAttributeName(mapping: SearchConditionBuilder.PropertyMapping) -> String? {
        var mdimporterCandidate: String?

        for rawKey in mapping.systemKeys {
            let parsed = SystemKeyParser.parse(rawKey)
            let prefix = parsed.prefix
            let symbol = parsed.symbol

            if prefix == "mditem", symbol.hasPrefix("kMD") {
                return symbol
            }
            if prefix == "mdimporter", symbol.isEmpty == false, mdimporterCandidate == nil {
                mdimporterCandidate = symbol
                continue
            }
            if prefix.isEmpty, symbol.hasPrefix("kMDItem") {
                return symbol
            }
        }

        return mdimporterCandidate
    }

    private func buildClause(
        attribute: String,
        typeKey: String,
        dateMdqueryOperator: DateMdqueryOperator?,
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
            guard let dateMdqueryOperator else {
                throw CompileError.unsupportedOperator(
                    propertyKey: condition.propertyKey,
                    operatorCode: condition.operator,
                )
            }
            return try buildDateClause(
                attribute: attribute,
                condition: condition,
                dateMdqueryOperator: dateMdqueryOperator,
            )
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
            let exact = "\(attribute) == \"\(escaped)\""
            let withExtension = "\(attribute) == \"\(escaped).*\""
            eqClause = "(\(exact) || \(withExtension))"
        } else {
            eqClause = "\(attribute) == \"\(escaped)\""
        }

        switch condition.operator {
        case "eq":
            return eqClause
        case "neq":
            if condition.propertyKey == "name_stem" {
                let exact = "\(attribute) != \"\(escaped)\""
                let withExtension = "\(attribute) != \"\(escaped).*\""
                return "(\(exact) && \(withExtension))"
            }
            return "\(attribute) != \"\(escaped)\""
        case "cn":
            return "\(attribute) == \"*\(escaped)*\""
        case "nc":
            return "\(attribute) != \"*\(escaped)*\""
        case "sw":
            return "\(attribute) == \"\(escaped)*\""
        case "ew":
            return "\(attribute) == \"*\(escaped)\""
        case "rx":
            return "\(attribute) == \"\(normalizeWildcardPattern(escaped))\""
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
                .map { "\(attribute) == \"\(escapeLiteral($0))\"" }
            if condition.operator == "none" {
                return "(" + comparisons
                    .map { $0.replacingOccurrences(of: "==", with: "!=") }
                    .joined(separator: " && ") + ")"
            }
            return "(" + comparisons.joined(separator: " || ") + ")"
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
            .map { "\(attribute) == \"\(escapeLiteral($0))\"" }

        switch condition.operator {
        case "any":
            return "(" + comparisons.joined(separator: " || ") + ")"
        case "none":
            return "(" + comparisons
                .map { $0.replacingOccurrences(of: "==", with: "!=") }
                .joined(separator: " && ") + ")"
        case "all":
            return "(" + comparisons.joined(separator: " && ") + ")"
        case "miss":
            return "(" + comparisons
                .map { $0.replacingOccurrences(of: "==", with: "!=") }
                .joined(separator: " || ") + ")"
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
                return "(\(attribute) < \(formatNumber(lower)) || \(attribute) > \(formatNumber(upper)))"
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

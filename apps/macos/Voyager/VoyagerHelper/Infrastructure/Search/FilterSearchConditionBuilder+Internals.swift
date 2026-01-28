import Foundation
@preconcurrency import GRDB

extension FilterSearchConditionBuilder {
    private struct KindClauseInput {
        let field: String
        let mapping: PropertyMapping
        let operatorMeta: OperatorDefinition
        let operatorCode: String
        let value: JSONValue?
        let jsonPath: String?
    }

    func buildDbClause(
        mapping: PropertyMapping,
        operatorMeta: OperatorDefinition,
        operatorCode: String,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        var field = mapping.key
        if mapping.type == "date" || mapping.type == "datetime" {
            field = "DATE(\(field))"
        }

        if mapping.type == "string_list" {
            return try buildDbStringListClause(
                field: field,
                operatorMeta: operatorMeta,
                value: value,
                binder: &binder,
            )
        }

        return try buildKindClause(
            input: KindClauseInput(
                field: field,
                mapping: mapping,
                operatorMeta: operatorMeta,
                operatorCode: operatorCode,
                value: value,
                jsonPath: nil,
            ),
            binder: &binder,
        )
    }

    func buildJsonClause(
        mapping: PropertyMapping,
        operatorMeta: OperatorDefinition,
        operatorCode: String,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        guard let propertyType = registry.propertyTypes[conditionTypeKey(for: mapping.type) ?? ""] else {
            throw BuilderError(message: "Missing property_types for \(mapping.type)")
        }
        guard let castType = propertyType.sqlCast else {
            throw BuilderError(message: "Missing sql_cast for type '\(mapping.type)'")
        }
        guard let jsonPath = jsonPath(for: mapping.systemKeys) else {
            throw BuilderError(message: "Missing JSON path for '\(mapping.key)'")
        }
        var field = "CAST(json_extract(original_metadata, '\(jsonPath)') AS \(castType))"
        if mapping.type == "date" || mapping.type == "datetime" {
            field = "DATE(\(field))"
        }
        return try buildKindClause(
            input: KindClauseInput(
                field: field,
                mapping: mapping,
                operatorMeta: operatorMeta,
                operatorCode: operatorCode,
                value: value,
                jsonPath: jsonPath,
            ),
            binder: &binder,
        )
    }

    private func buildKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        guard let sqlKind = input.operatorMeta.sqlKind else {
            throw BuilderError(message: "Missing sql_kind for operator '\(input.operatorCode)'")
        }

        let handlers: [String: (KindClauseInput, inout ParamBinder) throws -> String] = [
            "exists": buildExistsKindClause,
            "empty": buildEmptyKindClause,
            "range": buildRangeKindClause,
            "like_prefix": buildLikePrefixKindClause,
            "like_suffix": buildLikeSuffixKindClause,
            "like_pattern": buildLikePatternKindClause,
            "comparison": buildComparisonKindClause,
            "string_list_any": buildStringListAnyKindClause,
            "string_list_not_any": buildStringListNotAnyKindClause,
            "string_list_all": buildStringListAllKindClause,
            "string_list_not_all": buildStringListNotAllKindClause,
        ]

        guard let handler = handlers[sqlKind] else {
            throw BuilderError(message: "Unsupported sql_kind: \(sqlKind)")
        }
        return try handler(input, &binder)
    }

    private func buildExistsKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) -> String {
        buildExistsClause(field: input.field, jsonPath: input.jsonPath, binder: &binder)
    }

    private func buildEmptyKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) -> String {
        buildEmptyClause(
            field: input.field,
            mapping: input.mapping,
            jsonPath: input.jsonPath,
            binder: &binder,
        )
    }

    private func buildRangeKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildRangeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            binder: &binder,
        )
    }

    private func buildLikePrefixKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildLikeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            prefix: true,
            suffix: false,
            binder: &binder,
        )
    }

    private func buildLikeSuffixKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildLikeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            prefix: false,
            suffix: true,
            binder: &binder,
        )
    }

    private func buildLikePatternKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildLikePatternClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            operatorCode: input.operatorCode,
            value: input.value,
            binder: &binder,
        )
    }

    private func buildComparisonKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildComparisonClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            binder: &binder,
        )
    }

    private func buildStringListAnyKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildStringListAnyClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
            binder: &binder,
        )
    }

    private func buildStringListNotAnyKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildStringListNotAnyClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
            binder: &binder,
        )
    }

    private func buildStringListAllKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildStringListAllClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
            binder: &binder,
        )
    }

    private func buildStringListNotAllKindClause(
        input: KindClauseInput,
        binder: inout ParamBinder,
    ) throws -> String {
        try buildStringListNotAllClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
            binder: &binder,
        )
    }

    private func buildExistsClause(
        field: String,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) -> String {
        guard let jsonPath else {
            return "\(field) IS NOT NULL"
        }
        let placeholder = binder.bind(jsonPath)
        return "json_type(original_metadata, \(placeholder)) IS NOT NULL"
    }

    private func buildEmptyClause(
        field: String,
        mapping: PropertyMapping,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) -> String {
        if mapping.type == "string_list", jsonPath != nil {
            let first = binder.bind(jsonPath)
            let second = binder.bind(jsonPath)
            let lengthClause = "json_array_length(original_metadata, {})"
            return "(\(String(format: lengthClause, first)) IS NULL OR \(String(format: lengthClause, second)) = 0)"
        }
        return "(\(field) IS NULL OR \(field) = '')"
    }

    private func buildDbStringListClause(
        field: String,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        guard let sqlKind = operatorMeta.sqlKind else {
            throw BuilderError(message: "Missing sql_kind for string_list operator")
        }

        if sqlKind == "exists" {
            return "\(field) IS NOT NULL"
        }
        if sqlKind == "empty" {
            return "(\(field) IS NULL OR \(field) = '')"
        }

        let values = try normalizeStringListValues(value)
        switch sqlKind {
        case "string_list_any":
            let placeholders = binder.bindMany(values)
            return "\(field) IN (\(placeholders))"
        case "string_list_not_any":
            let placeholders = binder.bindMany(values)
            return "\(field) NOT IN (\(placeholders))"
        case "string_list_all", "string_list_not_all":
            throw BuilderError(message: "Operator '\(operatorMeta.uiLabel ?? "")' not supported for DB string_list")
        default:
            throw BuilderError(message: "Unsupported string_list sql_kind: \(sqlKind)")
        }
    }

    private func buildRangeClause(
        field: String,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        guard case let .array(values)? = value, values.count == 2 else {
            throw BuilderError(message: "'\(operatorMeta.uiLabel ?? "")' requires [min, max]")
        }
        let start = binder.bind(values[0].databaseValue)
        let end = binder.bind(values[1].databaseValue)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return "\(field) \(sqlOperator) \(start) AND \(end)"
    }

    private func buildLikeClause(
        field: String,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
        prefix: Bool,
        suffix: Bool,
        binder: inout ParamBinder,
    ) throws -> String {
        guard case let .string(text)? = value else {
            throw BuilderError(message: "'\(operatorMeta.uiLabel ?? "")' requires string value")
        }
        var pattern = text
        if prefix {
            pattern = "\(pattern)%"
        }
        if suffix {
            pattern = "%\(pattern)"
        }
        let placeholder = binder.bind(pattern)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return "\(field) \(sqlOperator) \(placeholder)"
    }

    private func buildLikePatternClause(
        field: String,
        operatorMeta: OperatorDefinition,
        operatorCode: String,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        let normalized = normalizeLikePatternValue(operatorCode, value: value)
        let placeholder = binder.bind(normalized)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return "\(field) \(sqlOperator) \(placeholder)"
    }

    private func buildComparisonClause(
        field: String,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
        binder: inout ParamBinder,
    ) throws -> String {
        let placeholder = binder.bind(value?.databaseValue)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return "\(field) \(sqlOperator) \(placeholder)"
    }

    private func buildStringListAnyClause(
        field: String,
        value: JSONValue?,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) throws -> String {
        let values = try normalizeStringListValues(value)
        if jsonPath == nil {
            if values.count == 1 {
                let placeholder = binder.bind(values[0])
                return "\(field) = \(placeholder)"
            }
            let placeholders = binder.bindMany(values)
            return "\(field) IN (\(placeholders))"
        }
        let placeholders = binder.bindMany(values)
        let jsonPlaceholder = binder.bind(jsonPath)
        return "EXISTS (SELECT 1 FROM json_each(original_metadata, \(jsonPlaceholder)) WHERE value IN (\(placeholders)))"
    }

    private func buildStringListNotAnyClause(
        field: String,
        value: JSONValue?,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) throws -> String {
        let clause = try buildStringListAnyClause(
            field: field,
            value: value,
            jsonPath: jsonPath,
            binder: &binder,
        )
        return "NOT \(clause)"
    }

    private func buildStringListAllClause(
        field: String,
        value: JSONValue?,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) throws -> String {
        let values = try normalizeStringListValues(value)
        if jsonPath == nil {
            if values.count == 1 {
                let placeholder = binder.bind(values[0])
                return "\(field) = \(placeholder)"
            }
            return "1=0"
        }
        let placeholders = binder.bindMany(values)
        let jsonPlaceholder = binder.bind(jsonPath)
        let countPlaceholder = binder.bind(values.count)
        return "(SELECT COUNT(DISTINCT value) FROM json_each(original_metadata, \(jsonPlaceholder)) WHERE value IN (\(placeholders))) = \(countPlaceholder)"
    }

    private func buildStringListNotAllClause(
        field: String,
        value: JSONValue?,
        jsonPath: String?,
        binder: inout ParamBinder,
    ) throws -> String {
        let clause = try buildStringListAllClause(
            field: field,
            value: value,
            jsonPath: jsonPath,
            binder: &binder,
        )
        return "NOT (\(clause))"
    }

    private func normalizeStringListValues(_ value: JSONValue?) throws -> [DatabaseValueConvertible?] {
        let values: [JSONValue] = if case let .array(items)? = value {
            items
        } else if let value {
            [value]
        } else {
            []
        }

        guard !values.isEmpty else {
            throw BuilderError(message: "string_list operator requires non-empty value")
        }
        return values.map(\.databaseValue)
    }

    private func normalizeLikePatternValue(_ operatorCode: String, value: JSONValue?) -> DatabaseValueConvertible? {
        guard case let .string(text)? = value else {
            return value?.databaseValue
        }
        if ["cn", "nc"].contains(operatorCode), !text.contains("%") {
            return "%\(text)%"
        }
        return text
    }

    private func resolveSqlOperator(_ operatorMeta: OperatorDefinition) -> String {
        if let sqlOperator = operatorMeta.sqlOperator {
            return sqlOperator
        }
        guard let sqlKind = operatorMeta.sqlKind else {
            return ""
        }
        return kSqlKindDefaultOperators[sqlKind] ?? ""
    }
}

private extension JSONValue {
    var databaseValue: DatabaseValueConvertible? {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case .array:
            nil
        case .object:
            nil
        case .null:
            nil
        }
    }
}

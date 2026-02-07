import Foundation
import StructuredQueries

extension FilterSearchConditionBuilder {
    private struct KindClauseInput {
        let field: QueryFragment
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
    ) throws -> QueryFragment {
        var field = columnFragment(for: mapping.key)
        if mapping.type == "date" || mapping.type == "datetime" {
            field = QueryFragment.date(field)
        }

        if mapping.type == "string_list" {
            return try buildDbStringListClause(
                field: field,
                operatorMeta: operatorMeta,
                value: value,
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
        )
    }

    func buildJsonClause(
        mapping: PropertyMapping,
        operatorMeta: OperatorDefinition,
        operatorCode: String,
        value: JSONValue?,
    ) throws -> QueryFragment {
        guard let propertyType = registry.propertyTypes[conditionTypeKey(for: mapping.type) ?? ""] else {
            throw BuilderError(message: "Missing property_types for \(mapping.type)")
        }
        guard let castType = propertyType.sqlCast else {
            throw BuilderError(message: "Missing sql_cast for type '\(mapping.type)'")
        }
        guard let jsonPath = jsonPath(for: mapping.systemKeys) else {
            throw BuilderError(message: "Missing JSON path for '\(mapping.key)'")
        }
        let jsonPathBinding = QueryBinding.text(jsonPath)
        let metadataColumn: QueryFragment = "\(FilterSearchEntryTable.originalMetadata)"
        var field = QueryFragment.cast(
            QueryFragment.jsonExtract(metadataColumn, jsonPathBinding),
            as: castType,
        )
        if mapping.type == "date" || mapping.type == "datetime" {
            field = QueryFragment.date(field)
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
        )
    }

    private func buildKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        guard let sqlKind = input.operatorMeta.sqlKind else {
            throw BuilderError(message: "Missing sql_kind for operator '\(input.operatorCode)'")
        }

        let handlers: [String: (KindClauseInput) throws -> QueryFragment] = [
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
        return try handler(input)
    }

    private func buildExistsKindClause(
        input: KindClauseInput,
    ) -> QueryFragment {
        buildExistsClause(field: input.field, jsonPath: input.jsonPath)
    }

    private func buildEmptyKindClause(
        input: KindClauseInput,
    ) -> QueryFragment {
        buildEmptyClause(
            field: input.field,
            mapping: input.mapping,
            jsonPath: input.jsonPath,
        )
    }

    private func buildRangeKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildRangeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
        )
    }

    private func buildLikePrefixKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildLikeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            prefix: true,
            suffix: false,
        )
    }

    private func buildLikeSuffixKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildLikeClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
            prefix: false,
            suffix: true,
        )
    }

    private func buildLikePatternKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildLikePatternClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            operatorCode: input.operatorCode,
            value: input.value,
        )
    }

    private func buildComparisonKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildComparisonClause(
            field: input.field,
            operatorMeta: input.operatorMeta,
            value: input.value,
        )
    }

    private func buildStringListAnyKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildStringListAnyClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
        )
    }

    private func buildStringListNotAnyKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildStringListNotAnyClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
        )
    }

    private func buildStringListAllKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildStringListAllClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
        )
    }

    private func buildStringListNotAllKindClause(
        input: KindClauseInput,
    ) throws -> QueryFragment {
        try buildStringListNotAllClause(
            field: input.field,
            value: input.value,
            jsonPath: input.jsonPath,
        )
    }

    private func buildExistsClause(
        field: QueryFragment,
        jsonPath: String?,
    ) -> QueryFragment {
        guard let jsonPath else {
            return QueryFragment.isNotNull(field)
        }
        let jsonPathBinding = QueryBinding.text(jsonPath)
        let metadataColumn: QueryFragment = "\(FilterSearchEntryTable.originalMetadata)"
        return QueryFragment.isNotNull(
            QueryFragment.jsonType(metadataColumn, jsonPathBinding),
        )
    }

    private func buildEmptyClause(
        field: QueryFragment,
        mapping: PropertyMapping,
        jsonPath: String?,
    ) -> QueryFragment {
        if mapping.type == "string_list", jsonPath != nil {
            let jsonPathBinding = QueryBinding.text(jsonPath ?? "")
            let metadataColumn: QueryFragment = "\(FilterSearchEntryTable.originalMetadata)"
            let lengthClause = QueryFragment.jsonArrayLength(
                metadataColumn,
                jsonPathBinding,
            )
            let emptyClause = QueryFragment.eq(lengthClause, QueryBinding.int(0))
            return QueryFragment.group(
                [
                    QueryFragment.isNull(lengthClause),
                    emptyClause,
                ].joinedWithOr(),
            )
        }
        return QueryFragment.group(
            [
                QueryFragment.isNull(field),
                QueryFragment.eq(field, QueryBinding.text("")),
            ].joinedWithOr(),
        )
    }

    private func buildDbStringListClause(
        field: QueryFragment,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
    ) throws -> QueryFragment {
        guard let sqlKind = operatorMeta.sqlKind else {
            throw BuilderError(message: "Missing sql_kind for string_list operator")
        }

        if sqlKind == "exists" {
            return QueryFragment.isNotNull(field)
        }
        if sqlKind == "empty" {
            return QueryFragment.group(
                [
                    QueryFragment.isNull(field),
                    QueryFragment.eq(field, QueryBinding.text("")),
                ].joinedWithOr(),
            )
        }

        let values = try normalizeStringListValues(value)
        switch sqlKind {
        case "string_list_any":
            let placeholders = bindMany(values)
            return QueryFragment.inList(field, placeholders)
        case "string_list_not_any":
            let placeholders = bindMany(values)
            return QueryFragment.notInList(field, placeholders)
        case "string_list_all", "string_list_not_all":
            throw BuilderError(message: "Operator '\(operatorMeta.uiLabel ?? "")' not supported for DB string_list")
        default:
            throw BuilderError(message: "Unsupported string_list sql_kind: \(sqlKind)")
        }
    }

    private func buildRangeClause(
        field: QueryFragment,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
    ) throws -> QueryFragment {
        guard case let .array(values)? = value, values.count == 2 else {
            throw BuilderError(message: "'\(operatorMeta.uiLabel ?? "")' requires [min, max]")
        }
        let start = bind(values[0])
        let end = bind(values[1])
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return QueryFragment.between(field, op: sqlOperator, start: start, end: end)
    }

    private func buildLikeClause(
        field: QueryFragment,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
        prefix: Bool,
        suffix: Bool,
    ) throws -> QueryFragment {
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
        let placeholder = bind(.string(pattern))
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return QueryFragment.compare(field, op: sqlOperator, rhs: placeholder)
    }

    private func buildLikePatternClause(
        field: QueryFragment,
        operatorMeta: OperatorDefinition,
        operatorCode: String,
        value: JSONValue?,
    ) throws -> QueryFragment {
        let normalized = normalizeLikePatternValue(operatorCode, value: value)
        let placeholder = bind(normalized)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return QueryFragment.compare(field, op: sqlOperator, rhs: placeholder)
    }

    private func buildComparisonClause(
        field: QueryFragment,
        operatorMeta: OperatorDefinition,
        value: JSONValue?,
    ) throws -> QueryFragment {
        let placeholder = bind(value)
        let sqlOperator = resolveSqlOperator(operatorMeta)
        return QueryFragment.compare(field, op: sqlOperator, rhs: placeholder)
    }

    private func buildStringListAnyClause(
        field: QueryFragment,
        value: JSONValue?,
        jsonPath: String?,
    ) throws -> QueryFragment {
        let values = try normalizeStringListValues(value)
        if jsonPath == nil {
            if values.count == 1 {
                let placeholder = bind(values[0])
                return QueryFragment.eq(field, placeholder)
            }
            let placeholders = bindMany(values)
            return QueryFragment.inList(field, placeholders)
        }
        let placeholders = bindMany(values)
        let jsonPlaceholder = QueryBinding.text(jsonPath ?? "")
        let metadataColumn: QueryFragment = "\(FilterSearchEntryTable.originalMetadata)"
        return QueryFragment.jsonEachExists(
            field: metadataColumn,
            path: jsonPlaceholder,
            values: placeholders,
        )
    }

    private func buildStringListNotAnyClause(
        field: QueryFragment,
        value: JSONValue?,
        jsonPath: String?,
    ) throws -> QueryFragment {
        let clause = try buildStringListAnyClause(
            field: field,
            value: value,
            jsonPath: jsonPath,
        )
        return QueryFragment.not(clause)
    }

    private func buildStringListAllClause(
        field: QueryFragment,
        value: JSONValue?,
        jsonPath: String?,
    ) throws -> QueryFragment {
        let values = try normalizeStringListValues(value)
        if jsonPath == nil {
            if values.count == 1 {
                let placeholder = bind(values[0])
                return QueryFragment.eq(field, placeholder)
            }
            return QueryFragment.alwaysFalse
        }
        let placeholders = bindMany(values)
        let jsonPlaceholder = QueryBinding.text(jsonPath ?? "")
        let countPlaceholder = bind(QueryBinding.int(Int64(values.count)))
        let metadataColumn: QueryFragment = "\(FilterSearchEntryTable.originalMetadata)"
        return QueryFragment.jsonEachCountDistinctEquals(
            field: metadataColumn,
            path: jsonPlaceholder,
            values: placeholders,
            count: countPlaceholder,
        )
    }

    private func buildStringListNotAllClause(
        field: QueryFragment,
        value: JSONValue?,
        jsonPath: String?,
    ) throws -> QueryFragment {
        let clause = try buildStringListAllClause(
            field: field,
            value: value,
            jsonPath: jsonPath,
        )
        return QueryFragment.not(clause)
    }

    private func normalizeStringListValues(_ value: JSONValue?) throws -> [QueryBinding] {
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
        return values.map { binding(from: $0) }
    }

    private func normalizeLikePatternValue(_ operatorCode: String, value: JSONValue?) -> QueryBinding {
        guard case let .string(text)? = value else {
            return binding(from: value)
        }
        if ["cn", "nc"].contains(operatorCode), !text.contains("%") {
            return .text("%\(text)%")
        }
        return .text(text)
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

import Foundation
import VoyagerShared

extension SpotlightQueryCompiler {
    func buildDateClause(
        attribute: String,
        condition: SearchConditionPayload,
        dateMdqueryOperator: DateMdqueryOperator,
    ) throws -> String {
        switch dateMdqueryOperator {
        case .range, .notRange:
            try buildDateRangeClause(
                attribute: attribute,
                condition: condition,
                dateMdqueryOperator: dateMdqueryOperator,
            )
        case .eq, .neq, .gt, .gte, .lt, .lte:
            try buildDateComparisonClause(
                attribute: attribute,
                condition: condition,
                dateMdqueryOperator: dateMdqueryOperator,
            )
        }
    }

    private func buildDateRangeClause(
        attribute: String,
        condition: SearchConditionPayload,
        dateMdqueryOperator: DateMdqueryOperator,
    ) throws -> String {
        let (firstLiteral, secondLiteral) = try readDateRange(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let firstRange = try resolveDayRange(
            literal: firstLiteral,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let secondRange = try resolveDayRange(
            literal: secondLiteral,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

        let startDate = min(firstRange.start, secondRange.start)
        let endDate = max(firstRange.endExclusive, secondRange.endExclusive)
        let startExpr = dateExpression(SearchDateUtils.dayLiteral(startDate))
        let endExpr = dateExpression(SearchDateUtils.dayLiteral(endDate))

        if dateMdqueryOperator == .notRange {
            return "(\(attribute) < \(startExpr) || \(attribute) >= \(endExpr))"
        }
        return "(\(attribute) >= \(startExpr) && \(attribute) < \(endExpr))"
    }

    private func buildDateComparisonClause(
        attribute: String,
        condition: SearchConditionPayload,
        dateMdqueryOperator: DateMdqueryOperator,
    ) throws -> String {
        let literal = try readDateLiteral(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

        if SearchDateUtils.todayOffset(for: literal) != nil {
            return buildTodayDateComparisonClause(
                attribute: attribute,
                literal: literal,
                dateMdqueryOperator: dateMdqueryOperator,
            )
        }

        return try buildResolvedDateComparisonClause(
            attribute: attribute,
            literal: literal,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
            dateMdqueryOperator: dateMdqueryOperator,
        )
    }

    private func buildTodayDateComparisonClause(
        attribute: String,
        literal: String,
        dateMdqueryOperator: DateMdqueryOperator,
    ) -> String {
        let expression = dateExpression(literal)
        switch dateMdqueryOperator {
        case .eq:
            return "(\(attribute) == \(expression))"
        case .neq:
            return "(\(attribute) != \(expression))"
        case .gt:
            return "\(attribute) > \(expression)"
        case .gte:
            return "\(attribute) >= \(expression)"
        case .lt:
            return "\(attribute) < \(expression)"
        case .lte:
            return "\(attribute) <= \(expression)"
        case .range, .notRange:
            preconditionFailure("Today comparison clause does not support range operators")
        }
    }

    private func buildResolvedDateComparisonClause(
        attribute: String,
        literal: String,
        propertyKey: String,
        operatorCode: String,
        dateMdqueryOperator: DateMdqueryOperator,
    ) throws -> String {
        let dayRange = try resolveDayRange(
            literal: literal,
            propertyKey: propertyKey,
            operatorCode: operatorCode,
        )

        let startExpr = dateExpression(SearchDateUtils.dayLiteral(dayRange.start))
        let endExpr = dateExpression(SearchDateUtils.dayLiteral(dayRange.endExclusive))

        switch dateMdqueryOperator {
        case .eq:
            return "(\(attribute) >= \(startExpr) && \(attribute) < \(endExpr))"
        case .neq:
            return "(\(attribute) < \(startExpr) || \(attribute) >= \(endExpr))"
        case .gt:
            return "\(attribute) >= \(endExpr)"
        case .gte:
            return "\(attribute) >= \(startExpr)"
        case .lt:
            return "\(attribute) < \(startExpr)"
        case .lte:
            return "\(attribute) < \(endExpr)"
        case .range, .notRange:
            throw CompileError.unsupportedOperator(
                propertyKey: propertyKey,
                operatorCode: operatorCode,
            )
        }
    }

    private func resolveDayRange(
        literal: String,
        propertyKey: String,
        operatorCode: String,
    ) throws -> (start: Date, endExclusive: Date) {
        guard let (start, endExclusive) = SearchDateUtils.dayRange(for: literal) else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        return (start, endExclusive)
    }

    private func dateExpression(_ literal: String) -> String {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$time.") {
            return trimmed
        }

        let primary = trimmed
            .split(whereSeparator: { $0 == "T" || $0 == " " })
            .first
            .map(String.init) ?? trimmed

        if SearchDateUtils.isDateOnlyLiteral(primary) {
            return "$time.iso(\(primary))"
        }

        return "\"\(escapeLiteral(trimmed))\""
    }
}

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
        case .today:
            buildTodayClause(attribute: attribute)
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
        let (startExpr, endExpr) = try resolveSingleDateExpressions(
            literal: literal,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

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
        case .range, .notRange, .today:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func buildTodayClause(attribute: String) -> String {
        let startExpr = todayExpression(0)
        let endExpr = todayExpression(1)
        return "(\(attribute) >= \(startExpr) && \(attribute) < \(endExpr))"
    }

    private func resolveSingleDateExpressions(
        literal: String,
        propertyKey: String,
        operatorCode: String,
    ) throws -> (startExpr: String, endExpr: String) {
        if let offset = SearchDateUtils.todayOffset(for: literal) {
            return (todayExpression(offset), todayExpression(offset + 1))
        }

        guard let resolved = SearchDateUtils.resolveDateLiteral(literal) else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        guard let dayRange = SearchDateUtils.dayRange(for: resolved) else {
            throw CompileError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }

        return (
            dateExpression(SearchDateUtils.dayLiteral(dayRange.0)),
            dateExpression(SearchDateUtils.dayLiteral(dayRange.1)),
        )
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

    private func todayExpression(_ offset: Int) -> String {
        "$time.today(\(offset))"
    }
}

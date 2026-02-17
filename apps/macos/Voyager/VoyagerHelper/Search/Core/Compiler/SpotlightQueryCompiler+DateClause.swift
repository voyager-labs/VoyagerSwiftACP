import Foundation

extension SpotlightQueryCompiler {
    func buildDateClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        switch condition.operator {
        case "btw", "nbtw":
            return try buildDateRangeClause(attribute: attribute, condition: condition)
        case "eq", "neq", "gt", "gte", "lt", "lte":
            return try buildDateComparisonClause(attribute: attribute, condition: condition)
        default:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func buildDateRangeClause(
        attribute: String,
        condition: SearchConditionPayload,
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

        if condition.operator == "nbtw" {
            return "(\(attribute) < \(startExpr) || \(attribute) >= \(endExpr))"
        }
        return "(\(attribute) >= \(startExpr) && \(attribute) < \(endExpr))"
    }

    private func buildDateComparisonClause(
        attribute: String,
        condition: SearchConditionPayload,
    ) throws -> String {
        let literal = try readDateLiteral(
            condition.value,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let dayRange = try resolveDayRange(
            literal: literal,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

        let startExpr = dateExpression(SearchDateUtils.dayLiteral(dayRange.start))
        let endExpr = dateExpression(SearchDateUtils.dayLiteral(dayRange.endExclusive))

        switch condition.operator {
        case "eq":
            return "(\(attribute) >= \(startExpr) && \(attribute) < \(endExpr))"
        case "neq":
            return "(\(attribute) < \(startExpr) || \(attribute) >= \(endExpr))"
        case "gt":
            return "\(attribute) >= \(endExpr)"
        case "gte":
            return "\(attribute) >= \(startExpr)"
        case "lt":
            return "\(attribute) < \(startExpr)"
        case "lte":
            return "\(attribute) < \(endExpr)"
        default:
            throw CompileError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
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

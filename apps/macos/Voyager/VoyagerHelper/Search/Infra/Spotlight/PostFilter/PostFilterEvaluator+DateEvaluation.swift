import Foundation

extension PostFilterEvaluator {
    func evaluateDate(spec: ConditionSpec, rawValue: Any?) throws -> Bool {
        guard let lhs = normalizedDate(rawValue) else {
            return false
        }

        switch spec.condition.operator {
        case "eq", "neq", "gt", "gte", "lt", "lte":
            return try evaluateDateComparison(lhs: lhs, condition: spec.condition)
        case "btw", "nbtw":
            return try evaluateDateRange(lhs: lhs, condition: spec.condition)
        default:
            throw EvaluationError.unsupportedOperator(
                propertyKey: spec.condition.propertyKey,
                operatorCode: spec.condition.operator,
            )
        }
    }

    private func evaluateDateComparison(
        lhs: Date,
        condition: SearchConditionPayload,
    ) throws -> Bool {
        let rhs = try readDate(condition)
        let rhsRange = try dayRange(
            for: rhs,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

        switch condition.operator {
        case "eq":
            return lhs >= rhsRange.start && lhs < rhsRange.endExclusive
        case "neq":
            return lhs < rhsRange.start || lhs >= rhsRange.endExclusive
        case "gt":
            return lhs >= rhsRange.endExclusive
        case "gte":
            return lhs >= rhsRange.start
        case "lt":
            return lhs < rhsRange.start
        case "lte":
            return lhs < rhsRange.endExclusive
        default:
            throw EvaluationError.unsupportedOperator(
                propertyKey: condition.propertyKey,
                operatorCode: condition.operator,
            )
        }
    }

    private func evaluateDateRange(
        lhs: Date,
        condition: SearchConditionPayload,
    ) throws -> Bool {
        let (first, second) = try readDateRange(condition)
        let firstRange = try dayRange(
            for: first,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )
        let secondRange = try dayRange(
            for: second,
            propertyKey: condition.propertyKey,
            operatorCode: condition.operator,
        )

        let start = min(firstRange.start, secondRange.start)
        let endExclusive = max(firstRange.endExclusive, secondRange.endExclusive)
        let inRange = lhs >= start && lhs < endExclusive
        return condition.operator == "btw" ? inRange : !inRange
    }

    private func dayRange(
        for date: Date,
        propertyKey: String,
        operatorCode: String,
    ) throws -> (start: Date, endExclusive: Date) {
        guard let (start, endExclusive) = SearchDateUtils.dayRange(for: date) else {
            throw EvaluationError.invalidValue(propertyKey: propertyKey, operatorCode: operatorCode)
        }
        return (start, endExclusive)
    }
}

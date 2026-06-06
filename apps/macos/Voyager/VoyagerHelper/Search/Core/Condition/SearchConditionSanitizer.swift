import Foundation
import VoyagerShared

nonisolated struct SearchConditionSanitizer {
    private let conditionBuilder: SearchConditionBuilder

    init(conditionBuilder: SearchConditionBuilder) {
        self.conditionBuilder = conditionBuilder
    }

    nonisolated func isVisiblePropertyKey(_ key: String) -> Bool {
        guard let canonicalKey = canonicalPropertyKey(for: key),
              let mapping = conditionBuilder.propertyMap[canonicalKey]
        else {
            return false
        }
        return mapping.uiHidden == false
    }

    nonisolated func normalizeAndValidate(_ conditions: [SearchConditionPayload]) -> [SearchConditionPayload] {
        var result: [SearchConditionPayload] = []
        result.reserveCapacity(conditions.count)

        for condition in conditions {
            guard let normalized = normalize(condition) else {
                continue
            }
            guard isValid(normalized) else {
                continue
            }
            result.append(normalized)
        }

        return result
    }
}

private extension SearchConditionSanitizer {
    nonisolated func normalize(_ condition: SearchConditionPayload) -> SearchConditionPayload? {
        guard let canonicalKey = canonicalPropertyKey(for: condition.propertyKey),
              let canonicalOperator = conditionBuilder.canonicalOperatorCode(for: condition.operator)
        else {
            return nil
        }

        if canonicalOperator == "eq", condition.value == nil {
            return nil
        }

        if canonicalOperator == "rx", case let .string(text)? = condition.value {
            let normalized: String = if text.contains("%") {
                text
            } else if text.contains(".*") {
                text.replacingOccurrences(of: ".*", with: "%")
            } else {
                text
            }

            return SearchConditionPayload(
                propertyKey: canonicalKey,
                operator: canonicalOperator,
                value: .string(normalized),
            )
        }

        return SearchConditionPayload(
            propertyKey: canonicalKey,
            operator: canonicalOperator,
            value: condition.value,
        )
    }

    nonisolated func canonicalPropertyKey(for rawKey: String) -> String? {
        conditionBuilder.canonicalVisiblePropertyKey(for: rawKey)
    }

    nonisolated func isValid(_ condition: SearchConditionPayload) -> Bool {
        guard let mapping = conditionBuilder.propertyMap[condition.propertyKey],
              mapping.uiHidden == false
        else {
            return false
        }

        guard let typeKey = conditionBuilder.conditionTypeKey(for: mapping.type),
              let propertyType = conditionBuilder.registry.propertyTypes[typeKey]
        else {
            return false
        }

        guard propertyType.operators.contains(condition.operator),
              let operatorMeta = conditionBuilder.registry.operators[condition.operator]
        else {
            return false
        }

        if let allowedTypes = operatorMeta.allowedTypes,
           allowedTypes.contains(typeKey) == false
        {
            return false
        }

        do {
            try conditionBuilder.validateValue(
                operatorMeta.valueCount,
                operatorCode: condition.operator,
                value: condition.value,
                propertyKey: condition.propertyKey,
            )
            return true
        } catch {
            return false
        }
    }
}

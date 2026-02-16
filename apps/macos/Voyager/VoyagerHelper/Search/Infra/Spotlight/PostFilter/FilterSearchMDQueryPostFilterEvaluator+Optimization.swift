import Foundation

extension FilterSearchMDQueryPostFilterEvaluator {
    func shouldEvaluateFirst(_ lhs: ConditionSpec, _ rhs: ConditionSpec) -> Bool {
        if lhs.evaluationPriority != rhs.evaluationPriority {
            return lhs.evaluationPriority > rhs.evaluationPriority
        }
        return lhs.condition.propertyKey < rhs.condition.propertyKey
    }

    func orderedSystemKeys(from rawKeys: [String]) -> [SystemKey] {
        let parsed = rawKeys.map { rawKey in
            let parsed = SearchSystemKeyParser.parse(rawKey)
            return SystemKey(prefix: parsed.prefix, symbol: parsed.symbol)
        }
        return parsed.sorted { lhs, rhs in
            systemKeyRank(lhs.prefix) < systemKeyRank(rhs.prefix)
        }
    }

    func systemKeyRank(_ prefix: String) -> Int {
        switch prefix {
        case "mditem":
            0
        case "mdimporter":
            1
        case "nsurl":
            2
        default:
            3
        }
    }

    func evaluationPriority(
        typeKey: String,
        operatorCode: String,
        orderedSystemKeys: [SystemKey],
    ) -> Int {
        typeScore(for: typeKey)
            + operatorScore(for: operatorCode)
            + sourceScore(for: orderedSystemKeys)
    }

    private func typeScore(for typeKey: String) -> Int {
        switch typeKey {
        case "number", "date", "boolean":
            40
        case "categorical", "string_list":
            25
        case "string":
            15
        default:
            10
        }
    }

    private func operatorScore(for operatorCode: String) -> Int {
        switch operatorCode {
        case "eq", "neq", "gt", "gte", "lt", "lte", "btw", "nbtw", "any", "none", "all", "miss":
            50
        case "exists", "empty":
            45
        case "sw", "ew":
            25
        case "cn", "nc":
            20
        case "rx":
            5
        default:
            10
        }
    }

    private func sourceScore(for orderedSystemKeys: [SystemKey]) -> Int {
        if orderedSystemKeys.contains(where: { $0.prefix == "nsurl" }) {
            return -30
        }
        if orderedSystemKeys.isEmpty {
            return 30
        }
        return 0
    }
}

import Foundation

extension SpotlightQueryCompiler {
    struct NsurlBooleanPushdownRule {
        let trueClause: String
        let falseClause: String
    }

    static let nsurlBooleanPushdownRules: [String: NsurlBooleanPushdownRule] = {
        let isFolder = "kMDItemContentTypeTree == \"public.folder\""
        let isNotFolder = "kMDItemContentTypeTree != \"public.folder\""
        let isPackage = "kMDItemContentTypeTree == \"com.apple.package\""
        let isNotPackage = "kMDItemContentTypeTree != \"com.apple.package\""
        let isSymlink = "kMDItemContentTypeTree == \"public.symlink\""
        let isNotSymlink = "kMDItemContentTypeTree != \"public.symlink\""

        return [
            "is_directory": NsurlBooleanPushdownRule(trueClause: isFolder, falseClause: isNotFolder),
            "is_package": NsurlBooleanPushdownRule(trueClause: isPackage, falseClause: isNotPackage),
            "is_symbolic_link": NsurlBooleanPushdownRule(trueClause: isSymlink, falseClause: isNotSymlink),
            "is_regular_file": NsurlBooleanPushdownRule(
                trueClause: "(\(isNotFolder) && \(isNotSymlink))",
                falseClause: "(\(isFolder) || \(isSymlink))",
            ),
        ]
    }()

    func buildNsurlBooleanPushdownClause(condition: SearchConditionPayload) -> String? {
        guard condition.operator == "eq" else {
            return nil
        }
        guard let boolValue = condition.value?.boolValue else {
            return nil
        }
        guard let rule = Self.nsurlBooleanPushdownRules[condition.propertyKey] else {
            return nil
        }

        return boolValue ? rule.trueClause : rule.falseClause
    }
}

private extension JSONValue {
    var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .string(value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                return true
            }
            if ["false", "0", "no"].contains(normalized) {
                return false
            }
            return nil
        default:
            return nil
        }
    }
}

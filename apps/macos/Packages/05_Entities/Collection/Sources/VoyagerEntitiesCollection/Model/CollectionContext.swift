import Foundation

public struct CollectionContext: Equatable, Sendable {
    public var query: String
    public var scopes: [String]
    public var excludedScopes: [String]
    public var includeSubfolders: Bool
    public var includeDirectories: Bool
    public var conditions: [Condition]

    public init(
        query: String = "",
        scopes: [String] = [],
        excludedScopes: [String] = [],
        includeSubfolders: Bool = true,
        includeDirectories: Bool = false,
        conditions: [Condition] = [],
    ) {
        self.query = query
        self.scopes = scopes
        self.excludedScopes = excludedScopes
        self.includeSubfolders = includeSubfolders
        self.includeDirectories = includeDirectories
        self.conditions = conditions
    }
}

extension CollectionContext {
    func isSemanticallyEqual(to other: CollectionContext) -> Bool {
        normalizedQuery == other.normalizedQuery
            && normalizedScopes == other.normalizedScopes
            && normalizedExcludedScopes == other.normalizedExcludedScopes
            && includeSubfolders == other.includeSubfolders
            && includeDirectories == other.includeDirectories
            && normalizedConditions == other.normalizedConditions
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedScopes: [String] {
        scopes.map(normalizePath).sorted()
    }

    private var normalizedExcludedScopes: [String] {
        excludedScopes.map(normalizePath).sorted()
    }

    private var normalizedConditions: [ConditionSemanticSignature] {
        conditions.map(ConditionSemanticSignature.init).sorted()
    }

    private func normalizePath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}

private struct ConditionSemanticSignature: Comparable {
    let propertyKey: String
    let operatorCode: String?
    let values: [String]
    let isActive: Bool

    init(_ condition: Condition) {
        propertyKey = condition.property.key
        operatorCode = condition.operation?.code
        values = condition.values?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        isActive = condition.availability == .available
    }

    static func < (lhs: ConditionSemanticSignature, rhs: ConditionSemanticSignature) -> Bool {
        if lhs.propertyKey != rhs.propertyKey { return lhs.propertyKey < rhs.propertyKey }
        if lhs.operatorCode != rhs.operatorCode { return (lhs.operatorCode ?? "") < (rhs.operatorCode ?? "") }
        if lhs.values != rhs.values { return lhs.values.lexicographicallyPrecedes(rhs.values) }
        return !lhs.isActive && rhs.isActive
    }
}

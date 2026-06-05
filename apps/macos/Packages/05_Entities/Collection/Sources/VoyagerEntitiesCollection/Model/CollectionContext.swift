import Foundation

public struct CollectionContext: Equatable, Sendable {
    public var query: String
    public var scopes: [String]
    public var excludedScopes: [String]
    public var includeSubfolders: Bool
    public var conditions: [Condition]

    public init(
        query: String = "",
        scopes: [String] = [],
        excludedScopes: [String] = [],
        includeSubfolders: Bool = true,
        conditions: [Condition] = [],
    ) {
        self.query = query
        self.scopes = scopes
        self.excludedScopes = excludedScopes
        self.includeSubfolders = includeSubfolders
        self.conditions = conditions
    }
}

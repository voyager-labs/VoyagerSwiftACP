import Foundation

public struct CollectionContext: Equatable, Sendable {
    public var query: String
    public var scopes: [String]
    public var conditions: [Condition]

    public init(query: String = "", scopes: [String] = [], conditions: [Condition] = []) {
        self.query = query
        self.scopes = scopes
        self.conditions = conditions
    }
}

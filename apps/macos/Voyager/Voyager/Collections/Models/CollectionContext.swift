import Foundation

struct CollectionContext: Equatable, Sendable {
    var query: String
    var scopes: [String]
    var conditions: [Condition]
}

import Foundation

struct CollectionContext: Equatable, Sendable {
    var query: String
    var scopes: [String]
    var includeSubfolders: Bool = true
    var conditions: [Condition]
}

import Foundation
@preconcurrency import GRDB

struct FilterSearchScopeBuilder: Sendable {
    func buildScopeClause(scopes: [String]) -> (String, [String: DatabaseValueConvertible?]) {
        guard !scopes.isEmpty else {
            return ("1=1", [:])
        }

        var clauses: [String] = []
        var arguments: [String: DatabaseValueConvertible?] = [:]

        for (index, scope) in scopes.enumerated() {
            var normalized = scope
            while normalized.hasSuffix("/") {
                normalized.removeLast()
            }
            let baseKey = "s\(index)"
            let childKey = "s\(index)_child"
            clauses.append("dir_path = :\(baseKey) OR dir_path LIKE :\(childKey)")
            arguments[baseKey] = normalized
            arguments[childKey] = "\(normalized)/%"
        }

        if clauses.count == 1 {
            return (clauses[0], arguments)
        }
        return ("(\(clauses.joined(separator: " OR ")))", arguments)
    }
}

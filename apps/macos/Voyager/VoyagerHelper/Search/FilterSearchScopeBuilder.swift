import Foundation
import StructuredQueries

struct FilterSearchScopeBuilder: Sendable {
    func buildScopePredicate(scopes: [String]) -> QueryFragment {
        guard !scopes.isEmpty else {
            return .alwaysTrue
        }

        var clauses: [QueryFragment] = []

        for scope in scopes {
            var normalized = scope
            while normalized.hasSuffix("/") {
                normalized.removeLast()
            }

            let dirPath: QueryFragment = "\(FilterSearchEntryTable.dirPath)"
            let baseBinding = QueryBinding.text(normalized)
            let childBinding = QueryBinding.text("\(normalized)/%")
            let clause = QueryFragment.group(
                [
                    QueryFragment.eq(dirPath, baseBinding),
                    QueryFragment.like(dirPath, childBinding),
                ].joinedWithOr(),
            )
            clauses.append(clause)
        }

        if clauses.count == 1 {
            return clauses[0]
        }
        return QueryFragment.group(clauses.joinedWithOr())
    }
}

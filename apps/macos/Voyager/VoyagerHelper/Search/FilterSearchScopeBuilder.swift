import Foundation
import StructuredQueries

struct FilterSearchScopeBuilder: Sendable {
    func buildScopePredicate(scopes: [String]) -> QueryFragment {
        let normalizedScopes = normalizeScopes(scopes)

        guard !normalizedScopes.isEmpty else {
            return .alwaysTrue
        }

        var clauses: [QueryFragment] = []

        for normalized in normalizedScopes {
            let dirPath: QueryFragment = "\(FilterSearchEntryTable.dirPath)"
            let baseBinding = QueryBinding.text(normalized)
            let childBinding = QueryBinding.text(normalized == "/" ? "/%" : "\(normalized)/%")
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

    private nonisolated func normalizeScopes(_ scopes: [String]) -> [String] {
        var orderedUnique: [String] = []
        var seen: Set<String> = []

        for scope in scopes {
            guard let normalized = normalizeOne(scope),
                  seen.insert(normalized).inserted
            else {
                continue
            }
            orderedUnique.append(normalized)
        }

        guard !orderedUnique.isEmpty else {
            return []
        }

        let sorted = orderedUnique.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count < rhs.count
        }

        var reduced: [String] = []
        for path in sorted {
            if reduced.contains(where: { isContained(path: path, in: $0) }) {
                continue
            }
            reduced.append(path)
        }

        return reduced
    }

    private nonisolated func normalizeOne(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let absolutePath: String
        if expanded.hasPrefix("/") {
            absolutePath = URL(fileURLWithPath: expanded).standardizedFileURL.path
        } else {
            let currentDirectory = FileManager.default.currentDirectoryPath
            absolutePath = URL(
                fileURLWithPath: expanded,
                relativeTo: URL(fileURLWithPath: currentDirectory),
            )
            .standardizedFileURL
            .path
        }

        if absolutePath == "/" {
            return "/"
        }

        var normalized = absolutePath
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private nonisolated func isContained(path: String, in parent: String) -> Bool {
        if parent == "/" {
            return true
        }
        if path == parent {
            return true
        }
        return path.hasPrefix(parent + "/")
    }
}

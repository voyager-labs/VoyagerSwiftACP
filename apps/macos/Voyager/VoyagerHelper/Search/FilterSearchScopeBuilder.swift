import Foundation

struct FilterSearchScopeBuilder: Sendable {
    static func normalizeScopes(_ scopes: [String]) -> [String] {
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

    private static func normalizeOne(_ raw: String) -> String? {
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

    private static func isContained(path: String, in parent: String) -> Bool {
        if parent == "/" {
            return true
        }
        if path == parent {
            return true
        }
        return path.hasPrefix(parent + "/")
    }
}

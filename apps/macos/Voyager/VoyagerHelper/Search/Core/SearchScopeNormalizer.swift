import Foundation

struct SearchScopeNormalizer: Sendable {
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

        return orderedUnique
    }
}

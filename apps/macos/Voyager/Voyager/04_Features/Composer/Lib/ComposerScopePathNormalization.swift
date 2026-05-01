import Foundation

extension ComposerScopeUtils {
    static func normalizeScopePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rootScopePath }

        let standardized = (trimmed as NSString).standardizingPath
        guard !standardized.isEmpty, standardized != "." else { return rootScopePath }
        guard standardized != rootScopePath else { return rootScopePath }

        return standardized.hasSuffix(rootScopePath)
            ? String(standardized.dropLast())
            : standardized
    }

    static func isStrictDescendant(_ path: String, of base: String) -> Bool {
        let normalizedPath = normalizeScopePath(path)
        let normalizedBase = normalizeScopePath(base)

        guard normalizedPath != normalizedBase else { return false }
        if normalizedBase == rootScopePath {
            return normalizedPath != rootScopePath
        }

        return normalizedPath.hasPrefix(normalizedBase + rootScopePath)
    }

    static func canonicalizeScopeRule(
        bases: [String],
        exceptions: [String],
        includeSubfolders: Bool,
    ) -> (bases: [String], exceptions: [String]) {
        let normalizedBases = dedupeNormalizedPaths(bases)
        guard !normalizedBases.isEmpty else { return ([], []) }
        guard !normalizedBases.contains(rootScopePath) else { return ([], []) }

        let canonicalBases = normalizedBases.filter { $0 != rootScopePath }
        guard !canonicalBases.isEmpty else { return ([], []) }

        guard includeSubfolders else {
            return (canonicalBases, [])
        }

        let normalizedExceptions = dedupeNormalizedPaths(exceptions)
        let canonicalExceptions = canonicalizeExceptions(
            normalizedExceptions,
            bases: canonicalBases,
        )

        return (canonicalBases, canonicalExceptions)
    }

    private static func dedupeNormalizedPaths(_ paths: [String]) -> [String] {
        var result: [String] = []

        for path in paths.map(normalizeScopePath) where !result.contains(path) {
            result.append(path)
        }

        return result
    }

    private static func canonicalizeExceptions(_ exceptions: [String], bases: [String]) -> [String] {
        var result: [String] = []

        for path in exceptions
            .sorted(by: { lhs, rhs in lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count })
        {
            guard !bases.contains(path) else { continue }
            guard bases.contains(where: { isStrictDescendant(path, of: $0) }) else { continue }
            guard !result.contains(where: { isStrictDescendant(path, of: $0) || $0 == path }) else { continue }

            result.removeAll { isStrictDescendant($0, of: path) }

            result.append(path)
        }

        return result
    }
}

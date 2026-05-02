import Foundation

nonisolated func collectionChangeIsRelevant(
    changedPaths: [String],
    scopes: [String],
    excludedScopes: [String] = [],
    includeSubfolders: Bool = true,
) -> Bool {
    let normalizedScopes = scopes.compactMap { scope -> String? in
        guard !scope.isEmpty, scope.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: scope).standardizedFileURL.path
    }
    let normalizedExcludedScopes = excludedScopes.compactMap { scope -> String? in
        guard !scope.isEmpty, scope.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: scope).standardizedFileURL.path
    }
    let isDescendantOrEqual: @Sendable (String, String) -> Bool = { path, excludedScope in
        if path == excludedScope { return true }
        let prefix = excludedScope == "/" ? "/" : excludedScope + "/"
        return path.hasPrefix(prefix)
    }

    guard !normalizedScopes.isEmpty else {
        return true
    }

    return changedPaths.contains { changedPath in
        let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
        if normalizedExcludedScopes.contains(where: { isDescendantOrEqual(normalizedPath, $0) }) {
            return false
        }
        return normalizedScopes.contains { scopePath in
            guard includeSubfolders else {
                if normalizedPath == scopePath {
                    return true
                }
                let parentPath = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent().standardizedFileURL
                    .path
                return parentPath == scopePath
            }
            if normalizedPath == scopePath {
                return true
            }
            let scopePrefix = scopePath == "/" ? "/" : scopePath + "/"
            return normalizedPath.hasPrefix(scopePrefix)
        }
    }
}

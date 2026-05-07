import Foundation

public nonisolated func collectionChangeIsRelevant(changedPaths: [String], scopes: [String]) -> Bool {
    let normalizedScopes = scopes.compactMap { scope -> String? in
        guard !scope.isEmpty, scope.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: scope).standardizedFileURL.path
    }

    guard !normalizedScopes.isEmpty else {
        return true
    }

    return changedPaths.contains { changedPath in
        let normalizedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.path
        return normalizedScopes.contains { scopePath in
            if normalizedPath == scopePath {
                return true
            }
            let scopePrefix = scopePath == "/" ? "/" : scopePath + "/"
            return normalizedPath.hasPrefix(scopePrefix)
        }
    }
}

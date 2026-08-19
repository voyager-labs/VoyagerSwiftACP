import VoyagerShared

nonisolated public func collectionChangeIsRelevant(
    changedPaths: [String],
    scopes: [String],
    excludedScopes: [String] = [],
    includeSubfolders: Bool = true,
) -> Bool {
    let validScopes = scopes.filter { !$0.isEmpty && $0.hasPrefix("/") }
    let validExcludedScopes = excludedScopes.filter { !$0.isEmpty && $0.hasPrefix("/") }

    guard !validScopes.isEmpty else {
        return true
    }

    return changedPaths.contains { changedPath in
        if validExcludedScopes.contains(where: {
            FileChangeScopePolicy.affects(root: $0, path: changedPath, includeSubfolders: true)
        }) {
            return false
        }
        return validScopes.contains { scopePath in
            FileChangeScopePolicy.affects(
                root: scopePath,
                path: changedPath,
                includeSubfolders: includeSubfolders,
            )
        }
    }
}

import Foundation

enum ComposerScopeCandidateDisambiguation {
    private struct Source {
        let parentPath: String
        let parentComponents: [String]
        let parentLastComponent: String
        let storageKindKey: String
        let storageLocationLabel: String?
    }

    nonisolated static func locationMetadata(path: String)
        -> (locationIdentifier: String?, secondaryText: String?)
    {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        guard normalizedPath != ComposerScopeUtils.rootScopePath else {
            return (nil, nil)
        }

        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        let normalizedParentPath = ComposerScopeUtils.normalizeScopePath(parentPath)
        guard normalizedParentPath != ComposerScopeUtils.rootScopePath else {
            return (nil, nil)
        }

        return (normalizedParentPath, nil)
    }

    nonisolated static func texts(for items: [ComposerScopeUtils.DirectoryItem]) -> [String] {
        let sources = items.map { candidateSource(for: $0) }
        var disambiguationTexts = [String?](repeating: nil, count: sources.count)

        let groupedByParent = Dictionary(grouping: Array(sources.enumerated()), by: { $0.element.parentLastComponent })
        for entries in groupedByParent.values {
            guard let first = entries.first else { continue }
            if entries.count == 1, !first.element.parentLastComponent.isEmpty {
                disambiguationTexts[first.offset] = first.element.parentLastComponent
                continue
            }

            let clusterSources = entries.map(\.element)
            let assignedLabels = Set(disambiguationTexts.compactMap(\.self))

            if let labels = disambiguationLabels(
                for: clusterSources,
                existingLabels: assignedLabels,
            ) {
                for (entry, label) in zip(entries, labels) {
                    disambiguationTexts[entry.offset] = label
                }
                continue
            }

            for entry in entries {
                disambiguationTexts[entry.offset] = entry.element.parentPath
            }
        }

        return disambiguationTexts.map { $0 ?? "" }
    }

    private nonisolated static func disambiguationLabels(
        for sources: [Source],
        existingLabels: Set<String>,
    ) -> [String]? {
        if hasMixedStorageKinds(sources) {
            return uniqueStorageFallbackLabels(
                for: sources,
                existingLabels: existingLabels,
            )
        }

        if let suffixLabels = uniqueParentSuffixLabels(
            for: sources,
            existingLabels: existingLabels,
        ) {
            return suffixLabels
        }

        return nil
    }

    private nonisolated static func candidateSource(
        for item: ComposerScopeUtils.DirectoryItem,
    ) -> Source {
        let parentPath = normalizedParentPath(for: item)
        let parentComponents = pathComponents(parentPath)
        let parentLastComponent = parentComponents.last ?? item.name
        let (storageKindKey, storageLocationLabel) = storageMetadata(parentComponents: parentComponents)

        return Source(
            parentPath: parentPath,
            parentComponents: parentComponents,
            parentLastComponent: parentLastComponent,
            storageKindKey: storageKindKey,
            storageLocationLabel: storageLocationLabel,
        )
    }

    private nonisolated static func normalizedParentPath(for item: ComposerScopeUtils.DirectoryItem) -> String {
        if let locationIdentifier = item.locationIdentifier, !locationIdentifier.isEmpty {
            return ComposerScopeUtils.normalizeScopePath(locationIdentifier)
        }

        let normalizedPath = ComposerScopeUtils.normalizeScopePath(item.path)
        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        return ComposerScopeUtils.normalizeScopePath(parentPath)
    }

    private nonisolated static func pathComponents(_ path: String) -> [String] {
        ComposerScopeUtils.normalizeScopePath(path)
            .split(separator: Character(ComposerScopeUtils.rootScopePath))
            .map(String.init)
    }

    private nonisolated static func storageMetadata(
        parentComponents: [String],
    ) -> (String, String?) {
        guard let firstComponent = parentComponents.first else {
            return ("other", nil)
        }

        if firstComponent == "Volumes", parentComponents.count >= 2 {
            return ("volume", parentComponents[1])
        }

        if firstComponent == "Users", parentComponents.count >= 2 {
            return ("userHome", parentComponents[1])
        }

        return ("other", firstComponent)
    }

    private nonisolated static func hasMixedStorageKinds(_ sources: [Source]) -> Bool {
        Set(sources.map(\.storageKindKey)).count > 1
    }

    private nonisolated static func uniqueParentSuffixLabels(
        for sources: [Source],
        existingLabels: Set<String>,
    ) -> [String]? {
        let maxDepth = sources.map(\.parentComponents.count).max() ?? 0
        guard maxDepth >= 2 else { return nil }

        for depth in 2 ... maxDepth {
            let labels = sources.map { parentSuffixLabel(for: $0, depth: depth) }
            let labelSet = Set(labels)
            guard labelSet.count == labels.count else { continue }
            guard existingLabels.isDisjoint(with: labelSet) else { continue }
            return labels
        }

        return nil
    }

    private nonisolated static func parentSuffixLabel(
        for source: Source,
        depth: Int,
    ) -> String {
        let suffixComponents = source.parentComponents.suffix(depth)
        if suffixComponents.isEmpty {
            return source.parentPath
        }

        return suffixComponents.joined(separator: ComposerScopeUtils.rootScopePath)
    }

    private nonisolated static func uniqueStorageFallbackLabels(
        for sources: [Source],
        existingLabels: Set<String>,
    ) -> [String]? {
        let labels = sources.map { source -> String in
            let parentLabel = source.parentLastComponent.isEmpty ? source.parentPath : source.parentLastComponent
            let storageLabel = source.storageLocationLabel ?? source.parentPath
            return storageLabel + " • " + parentLabel
        }
        let labelSet = Set(labels)
        guard labelSet.count == labels.count else { return nil }
        guard existingLabels.isDisjoint(with: labelSet) else { return nil }
        return labels
    }
}

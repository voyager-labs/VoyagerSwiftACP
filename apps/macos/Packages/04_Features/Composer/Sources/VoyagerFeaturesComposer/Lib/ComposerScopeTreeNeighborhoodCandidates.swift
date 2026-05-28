import Foundation
import VoyagerEntitiesEntry

enum ComposerScopeTreeNeighborhoodCandidates {
    static func make(
        editingPath: String?,
        selection: ComposerScopeSelection,
        entryLoadingClient: EntryLoadingClient,
        maxSiblingCount: Int = 50,
    ) -> [ComposerScopeTreeSeedItem] {
        guard let editingPath else { return [] }

        let normalizedEditingPath = ComposerScopeUtils.normalizeScopePath(editingPath)
        guard normalizedEditingPath != ComposerScopeUtils.rootScopePath else { return [] }

        let parentPath = ComposerScopeUtils.normalizeScopePath(
            (normalizedEditingPath as NSString).deletingLastPathComponent,
        )
        let excludedSiblingPaths = Set([
            normalizedEditingPath,
        ] + selection.explicitBases.map { ComposerScopeUtils.normalizeScopePath($0.path) }
            + selection.exceptions.map { ComposerScopeUtils.normalizeScopePath($0.path) })

        var seedItems: [ComposerScopeTreeSeedItem] = []
        if let parentSeed = makeParentSeedItem(
            parentPath: parentPath,
            entryLoadingClient: entryLoadingClient,
        ) {
            seedItems.append(parentSeed)
        }

        seedItems.append(makeSeedItem(path: normalizedEditingPath, entryLoadingClient: entryLoadingClient))
        seedItems.append(contentsOf: makeSiblingSeedItems(
            parentPath: parentPath,
            excludedPaths: excludedSiblingPaths,
            entryLoadingClient: entryLoadingClient,
            maxSiblingCount: maxSiblingCount,
        ))

        return dedupedSeedItems(seedItems)
    }

    private static func makeParentSeedItem(
        parentPath: String,
        entryLoadingClient: EntryLoadingClient,
    ) -> ComposerScopeTreeSeedItem? {
        guard parentPath != ComposerScopeUtils.rootScopePath else { return nil }
        return makeSeedItem(path: parentPath, entryLoadingClient: entryLoadingClient)
    }

    private static func makeSiblingSeedItems(
        parentPath: String,
        excludedPaths: Set<String>,
        entryLoadingClient: EntryLoadingClient,
        maxSiblingCount: Int,
    ) -> [ComposerScopeTreeSeedItem] {
        Array(
            ComposerScopeChildDirectoryCandidates.make(
                parentPath: parentPath,
                entryLoadingClient: entryLoadingClient,
                maxCount: maxSiblingCount + excludedPaths.count,
            )
            .filter { !excludedPaths.contains(ComposerScopeUtils.normalizeScopePath($0.path)) }
            .prefix(maxSiblingCount),
        )
        .map {
            ComposerScopeTreeSeedItem(
                path: $0.path,
                name: $0.name,
                iconName: $0.iconName,
                locationIdentifier: $0.locationIdentifier,
                secondaryText: $0.secondaryText,
            )
        }
    }

    private static func makeSeedItem(
        path: String,
        entryLoadingClient: EntryLoadingClient,
    ) -> ComposerScopeTreeSeedItem {
        let normalizedPath = ComposerScopeUtils.normalizeScopePath(path)
        let locationMetadata = ComposerScopeCandidateDisambiguation.locationMetadata(path: normalizedPath)

        return ComposerScopeTreeSeedItem(
            path: normalizedPath,
            name: entryLoadingClient.displayName(normalizedPath),
            iconName: "folder",
            locationIdentifier: locationMetadata.locationIdentifier,
            secondaryText: locationMetadata.secondaryText,
        )
    }

    private static func dedupedSeedItems(_ items: [ComposerScopeTreeSeedItem]) -> [ComposerScopeTreeSeedItem] {
        var deduped: [ComposerScopeTreeSeedItem] = []
        var seenNormalizedPaths: Set<String> = []

        for item in items {
            let normalizedPath = ComposerScopeUtils.normalizeScopePath(item.path)
            guard seenNormalizedPaths.insert(normalizedPath).inserted else { continue }
            deduped.append(item)
        }

        return deduped
    }
}

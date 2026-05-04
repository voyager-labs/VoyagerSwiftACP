// TODO(sunset VOY-273): Temporary compatibility adapter — app-layer tag normalization using package types.
import Foundation

import VoyagerEntitiesEntry
import VoyagerEntitiesTag

enum EntryModelTagColorNormalizer {
    nonisolated static func normalize(_ entries: [EntryModel], favoriteTags: [Tag]) -> [EntryModel] {
        entries.map { normalize($0, favoriteTags: favoriteTags) }
    }

    nonisolated static func normalize(_ entry: EntryModel, favoriteTags: [Tag]) -> EntryModel {
        let normalizedTags = TagColorFallbackResolver.normalizedTags(entry.facets.tags, favoriteTags: favoriteTags)
        guard normalizedTags != entry.facets.tags else {
            return entry
        }

        return EntryModel(
            name: entry.name,
            fullPath: entry.fullPath,
            isFolder: entry.isFolder,
            isHidden: entry.isHidden,
            size: entry.size,
            modifiedDate: entry.modifiedDate,
            fileExtension: entry.fileExtension,
            facets: EntryFacets(
                createdDate: entry.facets.createdDate,
                addedDate: entry.facets.addedDate,
                lastOpenedDate: entry.facets.lastOpenedDate,
                kind: entry.facets.kind,
                creatorApplication: entry.facets.creatorApplication,
                tags: normalizedTags,
                supplementaryMetadata: entry.facets.supplementaryMetadata,
            ),
        )
    }
}

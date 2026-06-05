import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

enum EntryCollectionItemsConverter {
    static func convert(
        _ paths: [String],
        showHidden: Bool,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> [EntryModel] {
        let favoriteTags = FinderFavoritesTagClient.liveValue.favoriteTags()
        let converted: [EntryModel] = paths.compactMap { path -> EntryModel? in
            guard !path.isEmpty else { return nil }

            let url = URL(fileURLWithPath: path)
            return EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            )
        }
        let normalized = EntryModelTagColorNormalizer.normalize(converted, favoriteTags: favoriteTags)

        guard !showHidden else { return normalized }
        return normalized.filter { !$0.isHidden }
    }
}

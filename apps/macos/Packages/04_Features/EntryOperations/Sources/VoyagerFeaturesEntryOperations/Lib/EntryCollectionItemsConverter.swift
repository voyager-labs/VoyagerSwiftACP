import ComposableArchitecture
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
        @Dependency(\.finderFavoritesTagClient)
        var finderFavoritesTagClient: FinderFavoritesTagClient
        let converted: [EntryModel] = paths.compactMap { path -> EntryModel? in
            guard !path.isEmpty else { return nil }

            let url = URL(fileURLWithPath: path)
            return EntryModelConverterLive.convertURLToEntry(
                url,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            )
        }
        let normalized = EntryModelTagColorNormalizer.normalize(
            converted,
            favoriteTags: finderFavoritesTagClient.favoriteTags(),
        )

        guard !showHidden else { return normalized }
        return normalized.filter { !$0.isHidden }
    }
}

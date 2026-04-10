import Foundation

enum EntryCollectionItemsConverter {
    static func convert(
        _ items: [JSONValue],
        showHidden: Bool,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> [EntryModel] {
        let favoriteTags = FinderFavoritesTagClient.liveValue.favoriteTags()
        let converted: [EntryModel] = items.compactMap { value -> EntryModel? in
            guard case let .string(path) = value,
                  path.isEmpty == false
            else {
                return nil
            }

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

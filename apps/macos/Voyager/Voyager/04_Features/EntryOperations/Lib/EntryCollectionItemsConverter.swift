import Foundation

enum EntryCollectionItemsConverter {
    static func convert(
        _ items: [JSONValue],
        showHidden: Bool,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> [EntryModel] {
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

        guard !showHidden else { return converted }
        return converted.filter { !$0.isHidden }
    }
}

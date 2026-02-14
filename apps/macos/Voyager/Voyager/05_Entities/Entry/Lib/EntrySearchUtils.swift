import Foundation

// NOTE: 이건 뭐지?
enum EntrySearchUtils {
    nonisolated static func convertCollectionItems(
        _ items: [JSONValue],
        showHidden: Bool,
        entryClient: EntryClient,
        workspaceClient: WorkspaceClient,
    ) -> [Entry] {
        let converted: [Entry] = items.compactMap { value -> Entry? in
            guard case let .string(path) = value,
                  path.isEmpty == false
            else {
                return nil
            }

            let url = URL(fileURLWithPath: path)
            return EntryLoadUtils.convertURLToEntry(
                url,
                entryClient: entryClient,
                workspaceClient: workspaceClient,
            )
        }

        guard !showHidden else { return converted }
        return converted.filter { !$0.isHidden }
    }
}

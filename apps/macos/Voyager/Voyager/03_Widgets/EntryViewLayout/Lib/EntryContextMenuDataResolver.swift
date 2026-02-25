import ComposableArchitecture
import IdentifiedCollections

struct EntryContextMenuTagItem {
    let name: String
    let colorCode: Int
    let state: SelectionState

    enum SelectionState {
        case on
        case off
        case mixed
    }
}

enum EntryContextMenuDataResolver {
    static func selectedCount(selectedIds: Set<String>, fallbackEntry: EntryModel?) -> Int {
        selectedIds.isEmpty ? (fallbackEntry == nil ? 0 : 1) : selectedIds.count
    }

    static func resolveCompressExtract(selectedEntries: [EntryModel]) -> (Bool, Bool) {
        EntryContextMenuUtils.calculateCompressExtractOptions(
            selectedItems: IdentifiedArrayOf(uniqueElements: selectedEntries),
        )
    }

    static func resolveTags(selectedEntries: [EntryModel]) -> [EntryContextMenuTagItem] {
        let finderFavoritesTagClient = FinderFavoritesTagClient.liveValue
        return finderFavoritesTagClient.favoriteTags()
            .map { favoriteTag in
                let tagName = favoriteTag.name
                let taggedCount = selectedEntries.reduce(into: 0) { count, entry in
                    if entry.facets.tags?.contains(where: { $0.name == tagName }) == true {
                        count += 1
                    }
                }

                let state: EntryContextMenuTagItem.SelectionState = if taggedCount == 0 {
                    .off
                } else if taggedCount == selectedEntries.count {
                    .on
                } else {
                    .mixed
                }

                let colorCode = selectedEntries
                    .lazy
                    .compactMap { entry in
                        entry.facets.tags?.first(where: { $0.name == tagName })?.colorCode
                    }
                    .first ?? favoriteTag.colorCode

                return EntryContextMenuTagItem(
                    name: tagName,
                    colorCode: colorCode,
                    state: state,
                )
            }
    }

    static func resolveOpenWithMenuData(
        adapter: EntryViewLayoutAdapter,
        selectedEntries: [EntryModel],
    ) -> (Bool, [ApplicationInfo]) {
        adapter.actions.resolveOpenWithMenuData(selectedEntries)
    }
}

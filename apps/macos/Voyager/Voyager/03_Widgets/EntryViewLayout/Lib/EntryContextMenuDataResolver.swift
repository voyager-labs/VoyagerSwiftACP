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
    static func selectedCount(selectedIds: Set<String>, fallbackEntry: Entry?) -> Int {
        selectedIds.isEmpty ? (fallbackEntry == nil ? 0 : 1) : selectedIds.count
    }

    static func resolveCompressExtract(selectedEntries: [Entry]) -> (Bool, Bool) {
        EntryContextMenuUtils.calculateCompressExtractOptions(
            selectedItems: IdentifiedArrayOf(uniqueElements: selectedEntries),
        )
    }

    static func resolveTags(selectedEntries: [Entry]) -> [EntryContextMenuTagItem] {
        let finderFavoritesTagClient = FinderFavoritesTagClient.liveValue
        return finderFavoritesTagClient.favoriteTags()
            .map { favoriteTag in
                let tagName = favoriteTag.name
                let taggedCount = selectedEntries.reduce(into: 0) { count, entry in
                    if entry.tags?.contains(where: { $0.name == tagName }) == true {
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
                        entry.tags?.first(where: { $0.name == tagName })?.colorCode
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
        contentStore: StoreOf<FileManagerContentFeature>,
        selectedEntries: [Entry],
    ) -> (Bool, [ApplicationInfo]) {
        let selectedFiles = selectedEntries.filter { !$0.isDirectory }
        if selectedFiles.isEmpty {
            return (false, [])
        }

        if selectedFiles.count > 1 {
            contentStore.send(.entries(.delegate(.intent(.loadCommonApplicationsForFiles(files: selectedFiles)))))
        } else if let file = selectedFiles.first,
                  contentStore.state.entryOperations.applicationsForItems[file.fullPath] == nil
        {
            contentStore.send(.entries(.delegate(.intent(.loadApplicationsForFile(file: file)))))
        }

        let applications: [ApplicationInfo] = if selectedFiles.count > 1 {
            contentStore.state.entryOperations.commonApplicationsForSelectedFiles
        } else if let file = selectedFiles.first {
            contentStore.state.entryOperations.applicationsForItems[file.fullPath] ?? []
        } else {
            []
        }

        return (true, applications)
    }
}

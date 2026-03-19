import Foundation

struct EntryContextMenuTagSpec {
    let name: String
    let colorCode: Int
    let selection: EntryContextMenuTagSelection
}

enum EntryContextMenuTagSelection {
    case on
    case off
    case mixed
}

// 더 좋은 구조 생각
struct EntryContextMenuSpec {
    let selectedCount: Int
    let rowEntryPathForOpenInNewTab: String?
    let canPaste: Bool
    let showCompress: Bool
    let showExtract: Bool
    let isTrashFolder: Bool
    let openWithApplications: [ApplicationInfo]
    let showOpenWith: Bool
    let tags: [EntryContextMenuTagSpec]
}

enum EntryContextMenuSpecFactory {
    // swiftlint:disable:next function_parameter_count
    static func make(
        selectedIds: Set<EntryModel.ID>,
        selectedEntries: [EntryModel],
        rowEntry: EntryModel?,
        isTrashFolder: Bool,
        canPaste: Bool,
        favoriteTags: [Tag],
        openWithApplications: [ApplicationInfo],
    ) -> EntryContextMenuSpec {
        let effectiveSelectedCount: Int = if !selectedIds.isEmpty {
            selectedIds.count
        } else if rowEntry != nil {
            1
        } else {
            0
        }
        let showOpenWith = selectedEntries.contains { !$0.isFolder }
        let (showCompress, showExtract) = resolveCompressExtract(selectedEntries: selectedEntries)

        return .init(
            selectedCount: effectiveSelectedCount,
            rowEntryPathForOpenInNewTab: rowEntry?.isFolder == true ? rowEntry?.fullPath : nil,
            canPaste: canPaste,
            showCompress: showCompress,
            showExtract: showExtract,
            isTrashFolder: isTrashFolder,
            openWithApplications: openWithApplications,
            showOpenWith: showOpenWith,
            tags: resolveTags(selectedEntries: selectedEntries, favoriteTags: favoriteTags),
        )
    }

    private static func resolveCompressExtract(selectedEntries: [EntryModel]) -> (Bool, Bool) {
        let containsZipFiles = selectedEntries.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedEntries.contains { $0.fileExtension.lowercased() != "zip" }
        return (!containsZipFiles, containsZipFiles && !containsNonZipFiles)
    }

    private static func resolveTags(
        selectedEntries: [EntryModel],
        favoriteTags: [Tag],
    ) -> [EntryContextMenuTagSpec] {
        favoriteTags.map { favoriteTag in
            let tagName = favoriteTag.name
            let taggedCount = selectedEntries.reduce(into: 0) { count, entry in
                if entry.facets.tags?.contains(where: { $0.name == tagName }) == true {
                    count += 1
                }
            }

            let selection: EntryContextMenuTagSelection = if taggedCount == 0 {
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

            return .init(
                name: tagName,
                colorCode: colorCode,
                selection: selection,
            )
        }
    }
}

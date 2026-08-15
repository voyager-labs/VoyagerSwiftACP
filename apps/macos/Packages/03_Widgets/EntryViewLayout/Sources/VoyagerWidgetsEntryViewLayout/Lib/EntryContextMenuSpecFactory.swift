import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

struct EntryContextMenuTagSpec {
    let name: String
    let colorCode: Int
    let selection: EntryContextMenuTagSelection
}

struct EntryContextMenuTarget {
    let selectedIds: Set<EntryModel.ID>
    let entries: [EntryModel]

    static func resolve(
        displayEntries: [EntryModel],
        selectedIds: Set<EntryModel.ID>,
        rowEntry: EntryModel?,
    ) -> Self {
        let visibleIDs = Set(displayEntries.map(\.id))
        let validSelectedIDs = selectedIds.intersection(visibleIDs)
        let targetIDs: Set<EntryModel.ID> = if let rowEntry, !validSelectedIDs.contains(rowEntry.id) {
            [rowEntry.id]
        } else {
            validSelectedIDs
        }

        return .init(
            selectedIds: targetIDs,
            entries: displayEntries.filter { targetIDs.contains($0.id) },
        )
    }

    func isCurrent(
        displayEntries: [EntryModel],
        selectedIds: Set<EntryModel.ID>,
    ) -> Bool {
        guard !entries.isEmpty, selectedIds == self.selectedIds else { return false }
        let visibleIDs = Set(displayEntries.map(\.id))
        return selectedIds.isSubset(of: visibleIDs)
    }

    func containsBusyEntry(busyEntryPaths: Set<String>) -> Bool {
        entries.contains { busyEntryPaths.contains($0.fullPath) }
    }
}

enum EntryContextMenuTagSelection {
    case on
    case off
    case mixed
}

public enum TagMutationMode: String, Sendable, Equatable {
    case add
    case remove
}

struct EntryContextMenuSpec {
    let selectedCount: Int
    let rowEntryPathForOpenInNewWindow: String?
    let openInNewTabPaths: [String]?
    let serviceNames: [String]
    let canPaste: Bool
    let showCompress: Bool
    let showExtract: Bool
    let isTrashFolder: Bool
    let canPutBack: Bool
    let openWithApplications: [ApplicationInfo]
    let isOpenWithApplicationsLoading: Bool
    let showOpenWith: Bool
    let paletteTags: [EntryContextMenuTagSpec]
    let knownTags: [EntryContextMenuTagSpec]
}

enum EntryContextMenuSpecFactory {
    // swiftlint:disable:next function_parameter_count
    static func make(
        selectedIds: Set<EntryModel.ID>,
        selectedEntries: [EntryModel],
        rowEntry: EntryModel?,
        isTrashFolder: Bool,
        restorableTrashPaths: Set<String>,
        canPaste: Bool,
        favoriteTags: [Tag],
        openWithApplications: [ApplicationInfo],
        isOpenWithApplicationsLoading: Bool = false,
        serviceNames: [String] = [],
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
        let favoriteNames = favoriteTags.map(\.name)
        let selectedTagNames = selectedEntries.flatMap { $0.facets.tags?.map(\.name) ?? [] }
        let openInNewTabPaths = resolveOpenInNewTabPaths(selectedEntries: selectedEntries)

        return .init(
            selectedCount: effectiveSelectedCount,
            rowEntryPathForOpenInNewWindow: rowEntry?.isFolder == true ? rowEntry?.fullPath : nil,
            openInNewTabPaths: openInNewTabPaths,
            serviceNames: serviceNames,
            canPaste: canPaste,
            showCompress: showCompress,
            showExtract: showExtract,
            isTrashFolder: isTrashFolder,
            canPutBack: isTrashFolder
                && !selectedEntries.isEmpty
                && selectedEntries.allSatisfy { restorableTrashPaths.contains($0.fullPath) },
            openWithApplications: openWithApplications,
            isOpenWithApplicationsLoading: isOpenWithApplicationsLoading,
            showOpenWith: showOpenWith,
            paletteTags: resolveTags(
                names: stableDeduplicated(favoriteTags.prefix(7).map(\.name)),
                selectedEntries: selectedEntries,
                favoriteTags: favoriteTags,
            ),
            knownTags: resolveTags(
                names: stableDeduplicated(favoriteNames + selectedTagNames),
                selectedEntries: selectedEntries,
                favoriteTags: favoriteTags,
            ),
        )
    }

    private static func resolveCompressExtract(selectedEntries: [EntryModel]) -> (Bool, Bool) {
        let containsZipFiles = selectedEntries.contains { $0.fileExtension.lowercased() == "zip" }
        let containsNonZipFiles = selectedEntries.contains { $0.fileExtension.lowercased() != "zip" }
        return (!containsZipFiles, containsZipFiles && !containsNonZipFiles)
    }

    /// 모든 선택 항목이 폴더일 때만 display 순서의 폴더 경로를 반환하고, 그 외에는 nil이다.
    private static func resolveOpenInNewTabPaths(selectedEntries: [EntryModel]) -> [String]? {
        guard !selectedEntries.isEmpty,
              selectedEntries.allSatisfy(\.isFolder)
        else {
            return nil
        }
        return selectedEntries.map(\.fullPath)
    }

    private static func resolveTags(
        names: [String],
        selectedEntries: [EntryModel],
        favoriteTags: [Tag],
    ) -> [EntryContextMenuTagSpec] {
        names.map { tagName in
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

            let preferredColorCodes = selectedEntries
                .lazy
                .compactMap { entry in
                    entry.facets.tags?.first(where: { $0.name == tagName })?.colorCode
                }
            let colorCode = TagColorFallbackResolver.resolvedColorCode(
                tagName: tagName,
                preferredColorCodes: Array(preferredColorCodes),
                favoriteTags: favoriteTags,
            )

            return .init(
                name: tagName,
                colorCode: colorCode,
                selection: selection,
            )
        }
    }

    private static func stableDeduplicated(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }
}

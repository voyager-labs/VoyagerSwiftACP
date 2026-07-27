import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

public struct ContentProjection: Equatable, Sendable {
    public var entries: [EntryModel]
    public var isLoading: Bool
    public var sortKey: EntryViewLayoutSortKey
    public var sortOrder: VoyagerShared.SortOrder
    public var groupKey: EntryViewLayoutGroupKey
    public var collapsedGroups: Set<String>
    public var sections: [EntryViewLayoutSection]
    public var renamingItemId: EntryModel.ID?
    public var clipboardCutPaths: Set<String>
    public var busyEntryPaths: Set<String>
    public var openWithApplications: [ApplicationInfo]
    public var restorableTrashPaths: Set<String>
    public var trashDirectoryPath: String?

    public init(
        entries: [EntryModel],
        isLoading: Bool,
        sortKey: EntryViewLayoutSortKey,
        sortOrder: VoyagerShared.SortOrder,
        groupKey: EntryViewLayoutGroupKey,
        collapsedGroups: Set<String>,
        sections: [EntryViewLayoutSection],
        renamingItemId: EntryModel.ID?,
        clipboardCutPaths: Set<String>,
        busyEntryPaths: Set<String>,
        openWithApplications: [ApplicationInfo],
        restorableTrashPaths: Set<String>,
        trashDirectoryPath: String?,
    ) {
        self.entries = entries
        self.isLoading = isLoading
        self.sortKey = sortKey
        self.sortOrder = sortOrder
        self.groupKey = groupKey
        self.collapsedGroups = collapsedGroups
        self.sections = sections
        self.renamingItemId = renamingItemId
        self.clipboardCutPaths = clipboardCutPaths
        self.busyEntryPaths = busyEntryPaths
        self.openWithApplications = openWithApplications
        self.restorableTrashPaths = restorableTrashPaths
        self.trashDirectoryPath = trashDirectoryPath
    }
}

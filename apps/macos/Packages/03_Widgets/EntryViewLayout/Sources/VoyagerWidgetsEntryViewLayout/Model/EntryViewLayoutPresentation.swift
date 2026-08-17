import Foundation
import VoyagerEntitiesEntry

public struct EntryViewLayoutSection: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let colorCode: Int?
    public let items: [EntryModel]
    public let isCollapsed: Bool

    public init(
        id: String,
        title: String?,
        colorCode: Int?,
        items: [EntryModel],
        isCollapsed: Bool,
    ) {
        self.id = id
        self.title = title
        self.colorCode = colorCode
        self.items = items
        self.isCollapsed = isCollapsed
    }

    public var count: Int {
        items.count
    }

    public var visibleItems: [EntryModel] {
        isCollapsed ? [] : items
    }

    public static func ungrouped(items: [EntryModel]) -> Self {
        Self(
            id: "",
            title: nil,
            colorCode: nil,
            items: items,
            isCollapsed: false,
        )
    }
}

public struct EntryViewLayoutPresentation: Equatable, Sendable {
    public let sections: [EntryViewLayoutSection]
    public let selectedIds: Set<EntryModel.ID>
    public let openWithApplications: [ApplicationInfo]

    public init(
        sections: [EntryViewLayoutSection],
        selectedIds: Set<EntryModel.ID>,
        openWithApplications: [ApplicationInfo],
    ) {
        self.sections = sections
        self.selectedIds = selectedIds
        self.openWithApplications = openWithApplications
    }

    public var entries: [EntryModel] {
        sections.flatMap(\.items)
    }

    public var visibleEntries: [EntryModel] {
        sections.flatMap(\.visibleItems)
    }

    public func changes(from previous: Self) -> EntryViewLayoutPresentationChangeSet {
        let previousEntries = previous.entriesByID
        let currentEntries = entriesByID
        let previousIDs = Set(previousEntries.keys)
        let currentIDs = Set(currentEntries.keys)
        let retainedIDs = previousIDs.intersection(currentIDs)

        return EntryViewLayoutPresentationChangeSet(
            sectionStructureChanged: previous.sectionStructure != sectionStructure,
            insertedEntryIDs: currentIDs.subtracting(previousIDs),
            removedEntryIDs: previousIDs.subtracting(currentIDs),
            updatedEntryIDs: Set(retainedIDs.filter { previousEntries[$0] != currentEntries[$0] }),
            selectionChanged: previous.selectedIds != selectedIds,
            groupExpansionChanged: previous.groupExpansion != groupExpansion,
            openWithApplicationsChanged: previous.openWithApplications != openWithApplications,
        )
    }

    private var entriesByID: [EntryModel.ID: EntryModel] {
        entries.reduce(into: [:]) { entriesByID, entry in
            entriesByID[entry.id] = entry
        }
    }

    private var sectionStructure: [EntryViewLayoutSectionStructure] {
        sections.map { section in
            EntryViewLayoutSectionStructure(
                id: section.id,
                title: section.title,
                colorCode: section.colorCode,
                entryIDs: section.items.map(\.id),
            )
        }
    }

    private var groupExpansion: [String: Bool] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.isCollapsed) })
    }
}

public struct EntryViewLayoutPresentationChangeSet: Equatable, Sendable {
    public let sectionStructureChanged: Bool
    public let insertedEntryIDs: Set<EntryModel.ID>
    public let removedEntryIDs: Set<EntryModel.ID>
    public let updatedEntryIDs: Set<EntryModel.ID>
    public let selectionChanged: Bool
    public let groupExpansionChanged: Bool
    public let openWithApplicationsChanged: Bool
}

private struct EntryViewLayoutSectionStructure: Equatable {
    let id: String
    let title: String?
    let colorCode: Int?
    let entryIDs: [EntryModel.ID]
}

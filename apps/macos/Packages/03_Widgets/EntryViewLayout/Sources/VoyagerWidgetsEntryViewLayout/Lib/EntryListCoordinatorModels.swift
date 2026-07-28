import CoreGraphics
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared

struct EntryListCoordinatorRenderSnapshot: Equatable {
    let listVisibleColumns: [EntryListColumn]
    let listIconSize: CGFloat
    let listTextSize: CGFloat
    let entries: [EntryModel]
    let groupKey: GroupKey
    let groupedItems: [GroupedItems]
    let currentPath: String
    let thumbnailRenderVersion: Int
    let selectedIds: Set<EntryModel.ID>
    let clipboardItems: Set<String>
    let clipboardOperation: ClipboardOperation
    let renamingItemId: EntryModel.ID?
    let sortKey: SortKey
    let sortOrder: VoyagerShared.SortOrder
    let showHiddenFiles: Bool
    let shouldScrollToSelection: Bool
    let isDropTargeted: Bool
    let outlineProjection: EntryListOutlineProjection
    let isHierarchyOutlineEnabled: Bool

    init(state: EntryViewLayoutState) {
        listVisibleColumns = state.listVisibleColumns
        listIconSize = state.listIconSize
        listTextSize = state.listTextSize
        entries = state.entries
        groupKey = state.entryArrangements.groupKey
        groupedItems = state.entryArrangements.groupedItems
        currentPath = state.currentPath
        thumbnailRenderVersion = state.entryThumbnail.renderVersion
        selectedIds = state.selectedIds
        clipboardItems = Set(state.entryOperations.clipboardItems)
        clipboardOperation = state.entryOperations.clipboardOperation
        renamingItemId = state.entryOperations.renamingItemId
        sortKey = state.entryArrangements.sortKey
        sortOrder = state.entryArrangements.sortOrder
        showHiddenFiles = state.showHiddenFiles
        shouldScrollToSelection = state.shouldScrollToSelection
        isDropTargeted = state.isDropTargeted
        isHierarchyOutlineEnabled = state.mode == .list
            && !state.isCollectionMode
            && state.entryArrangements.groupKey == .none
            && !state.hierarchy.rootPath.isEmpty
        outlineProjection = EntryListOutlineProjection(
            revision: state.outlineProjectionRevision,
            rootEntries: state.entries,
            hierarchyState: state.hierarchy,
            context: .init(
                mode: state.mode,
                isNormalDirectoryPage: isHierarchyOutlineEnabled,
                hasActiveGrouping: state.entryArrangements.groupKey != .none,
            ),
            sortKey: state.entryArrangements.sortKey,
            sortOrder: state.entryArrangements.sortOrder,
        )
    }
}

enum EntryListOutlineItemKind {
    case group(name: String, colorCode: Int?, isCollapsed: Bool)
    case entry(EntryModel)
    case empty(parent: EntryModel.ID)
    case error(parent: EntryModel.ID, failure: EntryListHierarchyFailure)
}

final class EntryListOutlineItem: Hashable {
    let kind: EntryListOutlineItemKind
    let children: [EntryListOutlineItem]
    let id: String
    let isLoadingChildren: Bool

    init(
        kind: EntryListOutlineItemKind,
        children: [EntryListOutlineItem] = [],
        isLoadingChildren: Bool = false,
    ) {
        self.kind = kind
        self.children = children
        self.isLoadingChildren = isLoadingChildren
        switch kind {
        case let .group(name, _, _):
            id = "group:\(name)"
        case let .entry(entry):
            id = "entry:\(entry.id)"
        case let .empty(parent):
            id = "empty:\(parent)"
        case let .error(parent, _):
            id = "error:\(parent)"
        }
    }

    static func == (lhs: EntryListOutlineItem, rhs: EntryListOutlineItem) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

enum EntryListCoordinatorProjectionIntent: Equatable {
    case disclosureExpand(EntryModel.ID, revision: Int)
    case disclosureCollapse(EntryModel.ID, revision: Int)
    case retry(EntryModel.ID, revision: Int)
    case selection(Set<EntryModel.ID>, revision: Int)
    case activate(EntryModel.ID, revision: Int)
}

enum EntryListCoordinatorAcceptedIntent: Equatable {
    case folderExpansionRequested(EntryModel.ID)
    case folderCollapseRequested(EntryModel.ID)
    case folderRetryRequested(EntryModel.ID)
    case selection(Set<EntryModel.ID>)
    case navigate(EntryModel.ID)
}

@MainActor
final class EntryListCoordinatorProjectionSession {
    private(set) var renderedProjectionRevision: Int?
    private(set) var isApplyingStoreProjection = false
    private(set) var pendingProjection: EntryListOutlineProjection?

    func apply(
        _ projection: EntryListOutlineProjection,
        perform: (EntryListOutlineProjection, [EntryListOutlineItem]) -> Void,
    ) {
        guard renderedProjectionRevision.map({ projection.revision > $0 }) ?? true else { return }
        guard !isApplyingStoreProjection else {
            if pendingProjection.map({ projection.revision > $0.revision }) ?? true {
                pendingProjection = projection
            }
            return
        }

        isApplyingStoreProjection = true
        renderedProjectionRevision = projection.revision
        perform(projection, Self.makeOutlineItems(from: projection))
        isApplyingStoreProjection = false

        if let pendingProjection {
            self.pendingProjection = nil
            apply(pendingProjection, perform: perform)
        }
    }

    func accept(_ intent: EntryListCoordinatorProjectionIntent) -> EntryListCoordinatorAcceptedIntent? {
        guard !isApplyingStoreProjection else { return nil }
        let revision: Int = switch intent {
        case let .disclosureExpand(_, revision), let .disclosureCollapse(_, revision),
             let .retry(_, revision), let .selection(_, revision), let .activate(_, revision):
            revision
        }
        guard revision == renderedProjectionRevision else { return nil }

        switch intent {
        case let .disclosureExpand(id, _):
            return .folderExpansionRequested(id)
        case let .disclosureCollapse(id, _):
            return .folderCollapseRequested(id)
        case let .retry(id, _):
            return .folderRetryRequested(id)
        case let .selection(ids, _):
            return .selection(ids)
        case let .activate(id, _):
            return .navigate(id)
        }
    }

    private static func makeOutlineItems(from projection: EntryListOutlineProjection) -> [EntryListOutlineItem] {
        projection.rootItemIDs.map { makeOutlineItem($0, projection: projection) }
    }

    private static func makeOutlineItem(
        _ itemID: EntryListOutlineProjection.ItemID,
        projection: EntryListOutlineProjection,
    ) -> EntryListOutlineItem {
        let children = projection.childrenByParent[itemID, default: []].map {
            makeOutlineItem($0, projection: projection)
        }
        guard let payload = projection.itemPayloads[itemID] else {
            preconditionFailure("Projection item payload is missing")
        }

        let kind: EntryListOutlineItemKind = switch payload {
        case let .entry(entry, _): .entry(entry)
        case let .empty(parent): .empty(parent: parent)
        case let .error(parent, failure): .error(parent: parent, failure: failure)
        }
        let isLoadingChildren: Bool = if case let .entry(_, isLoadingChildren) = payload {
            isLoadingChildren
        } else {
            false
        }
        return EntryListOutlineItem(kind: kind, children: children, isLoadingChildren: isLoadingChildren)
    }
}

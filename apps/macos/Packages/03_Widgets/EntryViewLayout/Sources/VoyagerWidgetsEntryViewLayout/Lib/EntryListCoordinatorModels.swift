import CoreGraphics
import VoyagerEntitiesEntry
import VoyagerShared

struct EntryListCoordinatorRenderSnapshot: Equatable {
    let presentation: EntryViewLayoutPresentation
    let listVisibleColumns: [EntryListColumn]
    let listIconSize: CGFloat
    let listTextSize: CGFloat
    let entries: [EntryModel]
    let groupKey: EntryViewLayoutGroupKey
    let currentPath: String
    let outlineProjectionRevision: Int
    let selectedIds: Set<EntryModel.ID>
    let clipboardCutPaths: Set<String>
    let renamingItemId: EntryModel.ID?
    let sortKey: EntryViewLayoutSortKey
    let sortOrder: VoyagerShared.SortOrder
    let showHiddenFiles: Bool
    let shouldScrollToSelection: Bool
    let isDropTargeted: Bool
    let outlineProjection: EntryListOutlineProjection
    let isHierarchyOutlineEnabled: Bool

    init(state: EntryViewLayoutState) {
        presentation = state.presentation
        listVisibleColumns = state.listVisibleColumns
        listIconSize = state.listIconSize
        listTextSize = state.listTextSize
        entries = state.entries
        groupKey = state.groupKey
        currentPath = state.currentPath
        outlineProjectionRevision = state.outlineProjectionRevision
        selectedIds = state.selectedIds
        clipboardCutPaths = state.clipboardCutPaths
        renamingItemId = state.renamingItemId
        sortKey = state.sortKey
        sortOrder = state.sortOrder
        showHiddenFiles = state.showHiddenFiles
        shouldScrollToSelection = state.shouldScrollToSelection
        isDropTargeted = state.isDropTargeted
        isHierarchyOutlineEnabled = state.mode == .list
            && !state.isCollectionMode
            && state.groupKey == .none
            && !state.hierarchy.rootPath.isEmpty
        outlineProjection = EntryListOutlineProjection(
            revision: state.outlineProjectionRevision,
            rootEntries: state.entries,
            hierarchyState: state.hierarchy,
            context: .init(
                mode: state.mode,
                isNormalDirectoryPage: isHierarchyOutlineEnabled,
                hasActiveGrouping: state.groupKey != .none,
            ),
            sortKey: state.sortKey.sharedSortKey,
            sortOrder: state.sortOrder,
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
    var kind: EntryListOutlineItemKind
    let children: [EntryListOutlineItem]
    let id: String
    var isLoadingChildren: Bool

    init(
        kind: EntryListOutlineItemKind,
        children: [EntryListOutlineItem] = [],
        isLoadingChildren: Bool = false,
        identityScope: String? = nil,
    ) {
        self.kind = kind
        self.children = children
        self.isLoadingChildren = isLoadingChildren
        switch kind {
        case let .group(name, _, _):
            id = "group:\(name)"
        case let .entry(entry):
            id = ["entry", identityScope, entry.id].compactMap(\.self).joined(separator: ":")
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

    func apply(_ payload: EntryListOutlineProjection.ItemPayload) {
        switch payload {
        case let .entry(entry, isLoadingChildren):
            kind = .entry(entry)
            self.isLoadingChildren = isLoadingChildren
        case let .empty(parent):
            kind = .empty(parent: parent)
            isLoadingChildren = false
        case let .error(parent, failure):
            kind = .error(parent: parent, failure: failure)
            isLoadingChildren = false
        }
    }
}

enum EntryListCoordinatorProjectionIntent: Equatable {
    case disclosureExpand(EntryModel.ID, revision: Int)
    case disclosureCollapse(EntryModel.ID, revision: Int)
    case retry(EntryModel.ID, revision: Int)
}

@MainActor
final class EntryListCoordinatorProjectionSession {
    private(set) var renderedProjectionRevision: Int?
    private(set) var isApplyingStoreProjection = false
    private(set) var pendingProjection: EntryListOutlineProjection?
    private var renderedProjection: EntryListOutlineProjection?

    func reset() {
        renderedProjectionRevision = nil
        isApplyingStoreProjection = false
        pendingProjection = nil
        renderedProjection = nil
    }

    func apply(
        _ projection: EntryListOutlineProjection,
        perform: (EntryListOutlineProjection, [EntryListOutlineItem]) -> Void,
    ) {
        guard shouldReplace(projection, current: renderedProjection) else { return }
        guard !isApplyingStoreProjection else {
            if shouldReplace(projection, current: pendingProjection ?? renderedProjection) {
                pendingProjection = projection
            }
            return
        }

        isApplyingStoreProjection = true
        renderedProjectionRevision = projection.revision
        renderedProjection = projection
        perform(projection, Self.makeOutlineItems(from: projection))
        isApplyingStoreProjection = false

        if let pendingProjection {
            self.pendingProjection = nil
            apply(pendingProjection, perform: perform)
        }
    }

    private func shouldReplace(
        _ projection: EntryListOutlineProjection,
        current: EntryListOutlineProjection?,
    ) -> Bool {
        guard let current else { return true }
        guard projection.revision == current.revision else {
            return projection.revision > current.revision
        }
        return !projection.hasSameStructure(as: current)
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

import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

extension WorkspaceClient {
    func toShared() -> VoyagerShared.WorkspaceClient {
        VoyagerShared.WorkspaceClient(
            urlForApplication: urlForApplication,
            urlForApplicationToOpen: urlForApplicationToOpen,
            urlsForApplications: urlsForApplications,
            iconForFile: iconForFile,
            iconForType: iconForType,
            openApplication: openApplication,
            openURL: openURL,
            currentEvent: currentEvent,
            runningApplications: runningApplications,
            activateFileViewerSelecting: activateFileViewerSelecting,
            openURLsWithApplication: openURLsWithApplication,
            openApplicationAtURL: openApplicationAtURL,
            addWorkspaceNotificationObserver: addWorkspaceNotificationObserver,
            removeWorkspaceNotificationObserver: removeWorkspaceNotificationObserver,
        )
    }
}

@Reducer
struct EntryViewLayoutFeature {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.workspaceClient)
    private var workspaceClient

    var body: some Reducer<State, Action> {
        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryThumbnail, action: \.entryThumbnail) {
            EntryThumbnailFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        Reduce { state, action in
            switch action {
            case let .internal(.setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = rangeAnchorId
                state.shouldScrollToSelection = shouldScrollToSelection

                if let renamingId = state.entryOperations.renamingItemId {
                    let isRenamingItemSelected = ids == [renamingId]
                    if !isRenamingItemSelected {
                        return .send(.entryOperations(.edit(.cancelRename)))
                    }
                }

                return .none

            case let .internal(.applySelectAll(orderedItemIds)):
                let lastSelectedId = orderedItemIds.last
                state.selectedIds = Set(orderedItemIds)
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = lastSelectedId
                state.shouldScrollToSelection = false
                return .none

            case .internal(.applyClearSelection):
                state.selectedIds = []
                state.lastSelectedId = nil
                state.rangeAnchorId = nil
                state.shouldScrollToSelection = false
                return .none

            case let .internal(.applySelectionOffset(offset, isShiftPressed, orderedItemIds)):
                guard !orderedItemIds.isEmpty else { return .none }

                guard let currentId = state.lastSelectedId,
                      let currentIndex = orderedItemIds.firstIndex(of: currentId)
                else {
                    let fallbackItemId = offset >= 0 ? orderedItemIds.first : orderedItemIds.last
                    guard let itemId = fallbackItemId else { return .none }
                    state.selectedIds = [itemId]
                    state.lastSelectedId = itemId
                    state.rangeAnchorId = itemId
                    state.shouldScrollToSelection = true
                    return .none
                }

                let targetIndex: Int
                if abs(offset) > 1 {
                    let columnCount = max(1, state.gridColumnCount)
                    let currentRow = currentIndex / columnCount
                    let currentCol = currentIndex % columnCount
                    let targetRow = currentRow + (offset > 0 ? 1 : -1)
                    let totalRows = (orderedItemIds.count + columnCount - 1) / columnCount

                    guard targetRow >= 0, targetRow < totalRows else { return .none }

                    let targetRowStart = targetRow * columnCount
                    let targetRowEnd = min(orderedItemIds.count - 1, (targetRow + 1) * columnCount - 1)
                    var candidate = targetRowStart + currentCol
                    if candidate > targetRowEnd {
                        candidate = targetRowEnd
                    }
                    targetIndex = candidate
                } else {
                    targetIndex = max(0, min(orderedItemIds.count - 1, currentIndex + offset))
                }

                let targetItemId = orderedItemIds[targetIndex]
                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? currentId
                    guard let anchorIndex = orderedItemIds.firstIndex(of: anchorId) else { return .none }
                    let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                    state.selectedIds = Set(orderedItemIds[range])
                    state.rangeAnchorId = anchorId
                } else {
                    state.selectedIds = [targetItemId]
                    state.rangeAnchorId = targetItemId
                }

                state.lastSelectedId = targetItemId
                state.shouldScrollToSelection = true
                return .none

            case let .internal(.updateGridColumnCount(count)):
                state.gridColumnCount = max(1, count)
                return .none

            case let .internal(.setListVisibleColumns(columns)):
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(columns)
                return .none

            case let .internal(.setListColumnVisibility(column, isVisible)):
                var nextColumns = state.listVisibleColumns
                if isVisible {
                    if !nextColumns.contains(column) {
                        nextColumns.append(column)
                    }
                } else if !EntryListColumn.requiredColumns.contains(column) {
                    nextColumns.removeAll { $0 == column }
                }
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(nextColumns)
                return .none

            case let .internal(.moveListColumn(from, to)):
                var nextColumns = EntryListColumn.normalizeVisibleColumns(state.listVisibleColumns)
                guard nextColumns.indices.contains(from) else { return .none }

                if from == to {
                    return .none
                }

                let moved = nextColumns.remove(at: from)
                let destination = max(0, min(to, nextColumns.count))
                nextColumns.insert(moved, at: destination)
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(nextColumns)
                return .none

            case .internal(.resetListVisibleColumns):
                state.listVisibleColumns = EntryListColumn.defaultVisibleColumns
                return .none

            case .internal(.resetScrollFlag):
                state.shouldScrollToSelection = false
                return .none

            case let .internal(.applyPreferences(preferences)):
                state.listIconSize = preferences.listIconSize
                state.listTextSize = preferences.listTextSize
                state.gridIconSize = preferences.gridIconSize
                state.gridTextSize = preferences.gridTextSize
                state.showHiddenFiles = preferences.showHiddenFiles
                return .none

            case let .view(.setDropTargeted(isTargeted)):
                state.isDropTargeted = isTargeted
                return .none

            case .view(.selectNextItem),
                 .view(.selectPreviousItem),
                 .view(.selectByOffset),
                 .view(.startDrag),
                 .view(.handleDrop),
                 .view(.dropItems),
                 .view(.openSelectedItem):
                return .none

            case let .internal(.setShowHiddenFiles(show)):
                state.showHiddenFiles = show
                return .none

            case .view(.toggleShowHiddenFiles):
                state.showHiddenFiles.toggle()
                return .none

            case let .internal(.setCollectionMode(isCollectionMode)):
                state.isCollectionMode = isCollectionMode
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.setCollectionItems(items)):
                state.collectionItems = IdentifiedArrayOf(uniqueElements: items)
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.applyCollectionSearchPaths(paths, showHidden)):
                let converted = EntryViewLayoutCollectionItemsConverter.convert(
                    paths,
                    showHidden: showHidden,
                    entryLoadingClient: entryLoadingClient,
                    workspaceClient: workspaceClient.toShared(),
                )
                state.collectionItems = IdentifiedArrayOf(uniqueElements: converted)
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.addCollectionPaths(paths)):
                guard state.isCollectionMode else { return .none }
                let restoredItems = EntryViewLayoutCollectionItemsConverter.convert(
                    paths,
                    showHidden: state.showHiddenFiles,
                    entryLoadingClient: entryLoadingClient,
                    workspaceClient: workspaceClient.toShared(),
                )
                guard !restoredItems.isEmpty else { return .none }

                let existingIDs = Set(state.collectionItems.map(\.id))
                let appendedItems = restoredItems.filter { !existingIDs.contains($0.id) }
                guard !appendedItems.isEmpty else { return .none }

                state.collectionItems.append(contentsOf: appendedItems)
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.removeCollectionPaths(paths)):
                guard state.isCollectionMode else { return .none }
                let mutatedPaths = Set(paths.map(Self.normalizedPath(_:)))
                guard !mutatedPaths.isEmpty else { return .none }

                let remainingItems = state.collectionItems.filter { item in
                    !Self.matchesAnyMutatedPath(item.fullPath, mutatedPaths: mutatedPaths)
                }
                guard remainingItems.count != state.collectionItems.count else {
                    return .none
                }

                state.collectionItems = IdentifiedArrayOf(uniqueElements: Array(remainingItems))
                Self.reconcileSelectionAfterCollectionMutation(&state)
                return Self.updateEntriesAndReapply(&state)

            case .internal(.clearCollectionPresentation):
                state.isCollectionMode = false
                state.collectionItems = []
                return Self.updateEntriesAndReapply(&state)

            case .delegate:
                return .none

            case .entryThumbnail:
                return .none

            case let .entryOperations(entryOperationsAction):
                switch entryOperationsAction {
                case .loading(.itemsLoaded):
                    return Self.updateEntriesAndReapply(&state)

                default:
                    return .none
                }

            case let .entryArrangements(entryArrangementsAction):
                switch entryArrangementsAction {
                case .delegate(.requestApply):
                    return .send(.entryArrangements(.apply(
                        items: state.entries,
                        isCollectionMode: state.isCollectionMode,
                    )))

                case let .delegate(.applied(sortedItems, _)):
                    state.entries = sortedItems
                    return .none

                default:
                    return .none
                }
            }
        }
    }

    // MARK: - Helpers

    static func updateEntriesAndReapply(_ state: inout State) -> Effect<Action> {
        state.entries = state.displayOrderItems
        return .send(.entryArrangements(.reapply))
    }

    static func reconcileSelectionAfterCollectionMutation(_ state: inout State) {
        let remainingIds = Set(state.collectionItems.map(\.id))
        state.selectedIds = state.selectedIds.intersection(remainingIds)

        if let lastSelectedId = state.lastSelectedId, !remainingIds.contains(lastSelectedId) {
            state.lastSelectedId = state.collectionItems.first { state.selectedIds.contains($0.id) }?.id
        }
        if let rangeAnchorId = state.rangeAnchorId, !remainingIds.contains(rangeAnchorId) {
            state.rangeAnchorId = state.lastSelectedId
        }
        state.shouldScrollToSelection = false
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func matchesAnyMutatedPath(_ itemPath: String, mutatedPaths: Set<String>) -> Bool {
        let normalizedItemPath = normalizedPath(itemPath)
        return mutatedPaths.contains { mutatedPath in
            normalizedItemPath == mutatedPath
                || normalizedItemPath.hasPrefix(mutatedPath == "/" ? "/" : mutatedPath + "/")
        }
    }
}

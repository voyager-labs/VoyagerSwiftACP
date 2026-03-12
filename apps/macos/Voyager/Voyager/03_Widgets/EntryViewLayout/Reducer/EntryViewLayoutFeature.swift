import ComposableArchitecture
import IdentifiedCollections

@Reducer
struct EntryViewLayoutFeature {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    var body: some Reducer<State, Action> {
        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
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

                let boundedDestination = max(0, min(to, nextColumns.count))
                if from == boundedDestination || from + 1 == boundedDestination {
                    return .none
                }

                let moved = nextColumns.remove(at: from)
                let destination = from < boundedDestination ? boundedDestination - 1 : boundedDestination
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

            case .delegate:
                return .none

            case let .entryOperations(entryOperationsAction):
                switch entryOperationsAction {
                case .itemsLoaded,
                     .collectionItemsLoadedFromSearch,
                     .setCollectionMode:
                    state.entries = state.entryOperations.displayOrderItems
                    return .send(.entryArrangements(.reapply))

                default:
                    return .none
                }

            case let .entryArrangements(entryArrangementsAction):
                switch entryArrangementsAction {
                case .delegate(.requestApply):
                    return .send(.entryArrangements(.apply(
                        items: state.entries,
                        isCollectionMode: state.entryOperations.loadingContext.isCollectionMode,
                    )))

                case let .delegate(.applied(sortedItems, isCollectionMode)):
                    if isCollectionMode {
                        state.entryOperations.loadingContext
                            .collectionItems = IdentifiedArray(uniqueElements: sortedItems)
                    } else {
                        state.entryOperations.loadingContext.items = IdentifiedArray(uniqueElements: sortedItems)
                    }
                    state.entries = sortedItems
                    return .none

                default:
                    return .none
                }
            }
        }
    }
}

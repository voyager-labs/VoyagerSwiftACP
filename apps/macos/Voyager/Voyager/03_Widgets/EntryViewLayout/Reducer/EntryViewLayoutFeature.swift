import ComposableArchitecture

@Reducer
struct EntryViewLayoutFeature {
    typealias State = EntryViewLayoutState
    typealias Action = EntryViewLayoutAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection):
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = rangeAnchorId
                state.shouldScrollToSelection = shouldScrollToSelection
                return .none

            case let .setSelectedIds(ids, lastSelectedId):
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = lastSelectedId
                state.shouldScrollToSelection = false
                return .none

            case let .setSelectedIdsFromLasso(ids, lastSelectedId):
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = lastSelectedId
                state.shouldScrollToSelection = false
                return .none

            case let .applySelectAll(orderedItemIds):
                let lastSelectedId = orderedItemIds.last
                state.selectedIds = Set(orderedItemIds)
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = lastSelectedId
                state.shouldScrollToSelection = false
                return .none

            case .applyClearSelection:
                state.selectedIds = []
                state.lastSelectedId = nil
                state.rangeAnchorId = nil
                state.shouldScrollToSelection = false
                return .none

            case let .applySelectionOffset(offset, isShiftPressed, orderedItemIds):
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

            case let .updateGridColumnCount(count):
                state.gridColumnCount = max(1, count)
                return .none

            case let .setListVisibleColumns(columns):
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(columns)
                return .none

            case let .setListColumnVisibility(column, isVisible):
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

            case let .moveListColumn(from, to):
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

            case .resetListVisibleColumns:
                state.listVisibleColumns = EntryListColumn.defaultVisibleColumns
                return .none

            case .resetScrollFlag:
                state.shouldScrollToSelection = false
                return .none

            case let .setDropTargeted(isTargeted):
                state.isDropTargeted = isTargeted
                return .none

            case let .startRename(id):
                state.renamingItemId = id
                return .none

            case let .setRenameState(id, text):
                state.renamingItemId = id
                state.renamingText = text
                return .none

            case let .updateRenamingText(text):
                state.renamingText = text
                return .none

            case .cancelRename:
                state.renamingItemId = nil
                state.renamingText = ""
                return .none

            case .commitRename,
                 .selectNextItem,
                 .selectPreviousItem,
                 .selectByOffset,
                 .startDrag,
                 .handleDrop,
                 .dropItems,
                 .openSelectedItem:
                return .none

            case let .setShowHiddenFiles(show):
                state.showHiddenFiles = show
                return .none

            case .toggleShowHiddenFiles:
                state.showHiddenFiles.toggle()
                return .none
            }
        }
    }
}

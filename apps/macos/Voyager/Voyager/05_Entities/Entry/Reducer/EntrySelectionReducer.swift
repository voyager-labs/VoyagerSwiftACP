import ComposableArchitecture

@Reducer
struct EntrySelectionReducer {
    typealias State = EntryState
    typealias Action = EntryAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setSelectedIds(ids, lastSelectedId):
                var renameEffect: Effect<Action> = .none
                let displayItems = state.displayItems

                if state.isRenaming {
                    renameEffect = .send(.commitRename)
                }

                let validIds = Set(displayItems.map(\.id))
                let normalizedIds = ids.intersection(validIds)

                state.shouldScrollToSelection = false
                state.selectedIds = normalizedIds

                let normalizedLastId: String? = if let lastSelectedId, normalizedIds.contains(lastSelectedId) {
                    lastSelectedId
                } else {
                    normalizedIds.first
                }

                state.lastSelectedId = normalizedLastId
                state.rangeAnchorId = normalizedLastId

                return .merge(
                    renameEffect,
                    EntryReducerSupport.preloadApplicationsEffect(
                        selectedIds: state.selectedIds,
                        items: displayItems,
                        currentItemId: normalizedLastId,
                    ),
                )

            case let .setSelectedIdsFromLasso(ids, lastSelectedId):
                var renameEffect: Effect<Action> = .none
                let displayItems = state.displayItems

                if state.isRenaming {
                    renameEffect = .send(.commitRename)
                }

                let validIds = Set(displayItems.map(\.id))
                let normalizedIds = ids.intersection(validIds)

                state.shouldScrollToSelection = false
                state.selectedIds = normalizedIds

                let normalizedLastId: String? = if let lastSelectedId, normalizedIds.contains(lastSelectedId) {
                    lastSelectedId
                } else {
                    normalizedIds.first
                }

                state.lastSelectedId = normalizedLastId
                state.rangeAnchorId = normalizedLastId

                return renameEffect

            case let .selectItem(id, isCommandPressed, isShiftPressed):
                var renameEffect: Effect<Action> = .none
                let displayItems = state.displayItems

                if state.isRenaming {
                    renameEffect = .send(.commitRename)
                }

                state.shouldScrollToSelection = false

                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? state.lastSelectedId ?? id
                    if let anchorIndex = Array(displayItems).firstIndex(where: { $0.id == anchorId }),
                       let currentIndex = Array(displayItems).firstIndex(where: { $0.id == id })
                    {
                        let itemsArray = Array(displayItems)
                        let range = min(anchorIndex, currentIndex) ... max(anchorIndex, currentIndex)
                        let rangeIds = itemsArray[range].map(\.id)
                        state.selectedIds = Set(rangeIds)
                        state.lastSelectedId = id
                        state.rangeAnchorId = anchorId
                    } else {
                        state.selectedIds = [id]
                        state.lastSelectedId = id
                        state.rangeAnchorId = id
                        return .merge(
                            renameEffect,
                            EntryReducerSupport.preloadApplicationsEffect(
                                selectedIds: state.selectedIds,
                                items: displayItems,
                                currentItemId: id,
                            ),
                        )
                    }
                } else if isCommandPressed {
                    if state.selectedIds.contains(id) {
                        state.selectedIds.remove(id)
                    } else {
                        state.selectedIds.insert(id)
                        state.lastSelectedId = id
                    }
                    state.rangeAnchorId = nil
                } else {
                    state.selectedIds = [id]
                    state.lastSelectedId = id
                    state.rangeAnchorId = id
                }

                return .merge(
                    renameEffect,
                    EntryReducerSupport.preloadApplicationsEffect(
                        selectedIds: state.selectedIds,
                        items: displayItems,
                        currentItemId: id,
                    ),
                )

            case .selectAll:
                state.selectedIds = Set(state.displayItems.map(\.id))
                if let lastItem = state.displayItems.last {
                    state.lastSelectedId = lastItem.id
                }

                return EntryReducerSupport.preloadApplicationsEffect(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )

            case .clearSelection:
                state.clearSelection()
                return .none

            case let .selectNextItem(isShiftPressed):
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else { return .none }

                if let lastId = state.lastSelectedId,
                   let currentIndex = displayItems.firstIndex(where: { $0.id == lastId })
                {
                    if currentIndex < displayItems.count - 1 {
                        let nextItem = displayItems[currentIndex + 1]
                        if isShiftPressed {
                            let anchorId = state.rangeAnchorId ?? lastId
                            guard let anchorIndex = displayItems.firstIndex(where: { $0.id == anchorId }) else {
                                return .none
                            }
                            let range = min(anchorIndex, currentIndex + 1) ... max(anchorIndex, currentIndex + 1)
                            state.selectedIds = Set(displayItems[range].map(\.id))
                            state.rangeAnchorId = anchorId
                        } else {
                            state.selectedIds = [nextItem.id]
                            state.rangeAnchorId = nil
                        }
                        state.lastSelectedId = nextItem.id
                        state.shouldScrollToSelection = true
                    }
                } else {
                    let firstItem = displayItems[0]
                    state.selectedIds = [firstItem.id]
                    state.lastSelectedId = firstItem.id
                    state.rangeAnchorId = nil
                    state.shouldScrollToSelection = true
                }

                return EntryReducerSupport.preloadApplicationsEffect(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )

            case let .selectPreviousItem(isShiftPressed):
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else { return .none }

                if let lastId = state.lastSelectedId,
                   let currentIndex = displayItems.firstIndex(where: { $0.id == lastId })
                {
                    if currentIndex > 0 {
                        let previousItem = displayItems[currentIndex - 1]
                        if isShiftPressed {
                            let anchorId = state.rangeAnchorId ?? lastId
                            guard let anchorIndex = displayItems.firstIndex(where: { $0.id == anchorId }) else {
                                return .none
                            }
                            let range = min(anchorIndex, currentIndex - 1) ... max(anchorIndex, currentIndex - 1)
                            state.selectedIds = Set(displayItems[range].map(\.id))
                            state.rangeAnchorId = anchorId
                        } else {
                            state.selectedIds = [previousItem.id]
                            state.rangeAnchorId = nil
                        }
                        state.lastSelectedId = previousItem.id
                        state.shouldScrollToSelection = true
                    }
                } else {
                    let lastItem = displayItems[displayItems.count - 1]
                    state.selectedIds = [lastItem.id]
                    state.lastSelectedId = lastItem.id
                    state.rangeAnchorId = nil
                    state.shouldScrollToSelection = true
                }

                return EntryReducerSupport.preloadApplicationsEffect(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )

            case let .selectByOffset(offset, isShiftPressed):
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else { return .none }

                guard let currentId = state.lastSelectedId,
                      let currentIndex = displayItems.firstIndex(where: { $0.id == currentId })
                else {
                    let targetItem = offset >= 0 ? displayItems.first : displayItems.last
                    guard let item = targetItem else { return .none }

                    state.selectedIds = [item.id]
                    state.lastSelectedId = item.id
                    state.rangeAnchorId = item.id
                    state.shouldScrollToSelection = true
                    return EntryReducerSupport.preloadApplicationsEffect(
                        selectedIds: state.selectedIds,
                        items: state.displayItems,
                        currentItemId: item.id,
                    )
                }

                var targetIndex: Int

                if abs(offset) > 1 {
                    let columnCount = state.gridColumnCount
                    let currentRow = currentIndex / columnCount
                    let currentCol = currentIndex % columnCount
                    let targetRow = currentRow + (offset > 0 ? 1 : -1)

                    let totalRows = (displayItems.count + columnCount - 1) / columnCount

                    if targetRow < 0 || targetRow >= totalRows {
                        return .none
                    }

                    let targetRowStart = targetRow * columnCount
                    let targetRowEnd = min(displayItems.count - 1, (targetRow + 1) * columnCount - 1)

                    targetIndex = targetRowStart + currentCol

                    if targetIndex > targetRowEnd {
                        targetIndex = targetRowEnd
                    }
                } else {
                    targetIndex = max(0, min(displayItems.count - 1, currentIndex + offset))
                }

                let targetItem = displayItems[targetIndex]

                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? currentId
                    guard let anchorIndex = displayItems.firstIndex(where: { $0.id == anchorId }) else { return .none }
                    let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                    state.selectedIds = Set(displayItems[range].map(\.id))
                    state.rangeAnchorId = anchorId
                } else {
                    state.selectedIds = [targetItem.id]
                    state.rangeAnchorId = targetItem.id
                }
                state.lastSelectedId = targetItem.id
                state.shouldScrollToSelection = true
                return EntryReducerSupport.preloadApplicationsEffect(
                    selectedIds: state.selectedIds,
                    items: state.displayItems,
                )

            case .resetScrollFlag:
                state.shouldScrollToSelection = false
                return .none

            default:
                return .none
            }
        }
    }
}

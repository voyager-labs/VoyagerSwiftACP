import ComposableArchitecture
import Foundation

/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    @ObservableState
    struct State: Equatable {
        var items: [FSItemModel] = []
        var selectedIds: Set<String> = []
        var lastSelectedId: String?
        var rangeAnchorId: String?
        var isLoading: Bool = false
    }

    enum Action: Equatable {
        case loadItems(path: String)
        case itemsLoaded([FSItemModel])
        case selectItem(id: String, isCommandPressed: Bool, isShiftPressed: Bool)
        case selectAll
        case clearSelection
        case selectNextItem(isShiftPressed: Bool)
        case selectPreviousItem(isShiftPressed: Bool)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loadItems(path):
                state.isLoading = true
                return .run { send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let contents = (try? FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []

                    let mapped: [FSItemModel] = contents.map { itemURL in
                        let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?
                            .isDirectory ?? false
                        return FSItemModel(
                            name: itemURL.lastPathComponent,
                            fullPath: itemURL.path,
                            isDirectory: isDirectory
                        )
                    }

                    let items = mapped.sorted { item1, item2 in
                        if item1.isDirectory != item2.isDirectory {
                            return item1.isDirectory
                        }
                        return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                    }

                    await send(.itemsLoaded(items))
                }

            case let .itemsLoaded(items):
                state.items = items
                state.isLoading = false
                return .none

            case let .selectItem(id, isCommandPressed, isShiftPressed):
                if isShiftPressed {
                    guard let lastId = state.lastSelectedId,
                          let lastIndex = state.items.firstIndex(where: { $0.id == lastId }),
                          let currentIndex = state.items.firstIndex(where: { $0.id == id })
                    else {
                        state.selectedIds = [id]
                        state.lastSelectedId = id
                        state.rangeAnchorId = nil
                        return .none
                    }

                    let range = min(lastIndex, currentIndex) ... max(lastIndex, currentIndex)
                    let rangeIds = state.items[range].map { $0.id }
                    state.selectedIds = Set(rangeIds)
                    state.lastSelectedId = id
                    state.rangeAnchorId = lastId
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
                    state.rangeAnchorId = nil
                }
                return .none

            case .selectAll:
                state.selectedIds = Set(state.items.map { $0.id })
                if let lastItem = state.items.last {
                    state.lastSelectedId = lastItem.id
                }
                return .none

            case .clearSelection:
                state.selectedIds = []
                return .none

            case let .selectNextItem(isShiftPressed):
                guard !state.items.isEmpty else {
                    return .none
                }

                if let lastId = state.lastSelectedId,
                   let currentIndex = state.items.firstIndex(where: { $0.id == lastId })
                {
                    if currentIndex < state.items.count - 1 {
                        let nextItem = state.items[currentIndex + 1]
                        if isShiftPressed {
                            let anchorId = state.rangeAnchorId ?? lastId
                            guard let anchorIndex = state.items.firstIndex(where: { $0.id == anchorId }) else {
                                return .none
                            }
                            let range = min(anchorIndex, currentIndex + 1) ... max(anchorIndex, currentIndex + 1)
                            state.selectedIds = Set(state.items[range].map { $0.id })
                            state.rangeAnchorId = anchorId
                        } else {
                            state.selectedIds = [nextItem.id]
                            state.rangeAnchorId = nil
                        }
                        state.lastSelectedId = nextItem.id
                    }
                } else {
                    let firstItem = state.items[0]
                    state.selectedIds = [firstItem.id]
                    state.lastSelectedId = firstItem.id
                    state.rangeAnchorId = nil
                }
                return .none

            case let .selectPreviousItem(isShiftPressed):
                guard !state.items.isEmpty else {
                    return .none
                }

                if let lastId = state.lastSelectedId,
                   let currentIndex = state.items.firstIndex(where: { $0.id == lastId })
                {
                    if currentIndex > 0 {
                        let previousItem = state.items[currentIndex - 1]
                        if isShiftPressed {
                            let anchorId = state.rangeAnchorId ?? lastId
                            guard let anchorIndex = state.items.firstIndex(where: { $0.id == anchorId }) else {
                                return .none
                            }
                            let range = min(anchorIndex, currentIndex - 1) ... max(anchorIndex, currentIndex - 1)
                            state.selectedIds = Set(state.items[range].map { $0.id })
                            state.rangeAnchorId = anchorId
                        } else {
                            state.selectedIds = [previousItem.id]
                            state.rangeAnchorId = nil
                        }
                        state.lastSelectedId = previousItem.id
                    }
                } else {
                    let lastItem = state.items[state.items.count - 1]
                    state.selectedIds = [lastItem.id]
                    state.lastSelectedId = lastItem.id
                    state.rangeAnchorId = nil
                }
                return .none
            }
        }
    }
}

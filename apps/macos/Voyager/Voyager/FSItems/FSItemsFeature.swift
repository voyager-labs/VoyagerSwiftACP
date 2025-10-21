import ComposableArchitecture
import Foundation

enum SortKey: String, Equatable, CaseIterable {
    case name
    case size
    case modified
    case type
}

enum SortOrder: String, Equatable {
    case ascending
    case descending
}

/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    static func sortItems(
        _ items: [FSItemModel],
        by sortKey: SortKey,
        order: SortOrder
    ) -> [FSItemModel] {
        items.sorted { item1, item2 in
            let comparison: ComparisonResult
            switch sortKey {
            case .name:
                comparison = item1.name.localizedCaseInsensitiveCompare(item2.name)
            case .size:
                comparison = item1.size < item2.size ? .orderedAscending :
                    item1.size > item2.size ? .orderedDescending : .orderedSame
            case .modified:
                comparison = item1.modifiedDate < item2.modifiedDate ? .orderedAscending :
                    item1.modifiedDate > item2.modifiedDate ? .orderedDescending : .orderedSame
            case .type:
                comparison = item1.fileExtension.localizedCaseInsensitiveCompare(item2.fileExtension)
            }

            switch order {
            case .ascending:
                return comparison == .orderedAscending
            case .descending:
                return comparison == .orderedDescending
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        var items: [FSItemModel] = []
        var selectedIds: Set<String> = []
        var lastSelectedId: String?
        var rangeAnchorId: String?
        var isLoading: Bool = false
        var showHiddenFiles: Bool = false

        var sortKey: SortKey = .name
        var sortOrder: SortOrder = .ascending
        var hasUserSetSortOrder: Bool = false

        var defaultSortOrder: SortOrder {
            switch sortKey {
            case .modified:
                return .descending
            case .name, .size, .type:
                return .ascending
            }
        }
    }

    enum Action: Equatable {
        case loadItems(path: String)
        case itemsLoaded([FSItemModel])
        case setShowHidden(Bool)
        case selectItem(id: String, isCommandPressed: Bool, isShiftPressed: Bool)
        case selectAll
        case clearSelection
        case selectNextItem(isShiftPressed: Bool)
        case selectPreviousItem(isShiftPressed: Bool)
        case selectByOffset(offset: Int, isShiftPressed: Bool)

        case setSortKey(SortKey)
        case setSortOrder(SortOrder)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .loadItems(path):
                state.isLoading = true
                let showHidden = state.showHiddenFiles
                return .run { [showHidden] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
                    let contents = (try? FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [
                            .isDirectoryKey,
                            .isHiddenKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                        ],
                        options: options
                    )) ?? []

                    let mapped: [FSItemModel] = contents.map { itemURL in
                        let values = try? itemURL.resourceValues(forKeys: [
                            .isDirectoryKey,
                            .isHiddenKey,
                            .fileSizeKey,
                            .contentModificationDateKey,
                        ])
                        let isDirectory = values?.isDirectory ?? false
                        let isHidden = values?.isHidden ?? false
                        let size = Int64(values?.fileSize ?? 0)
                        let modifiedDate = values?.contentModificationDate ?? Date()
                        let fileExtension = isDirectory ? "" : itemURL.pathExtension

                        return FSItemModel(
                            name: itemURL.lastPathComponent,
                            fullPath: itemURL.path,
                            isDirectory: isDirectory,
                            isHidden: isHidden,
                            size: size,
                            modifiedDate: modifiedDate,
                            fileExtension: fileExtension
                        )
                    }

                    await send(.itemsLoaded(mapped))
                }

            case let .setShowHidden(show):
                state.showHiddenFiles = show
                return .none

            case let .itemsLoaded(items):
                state.items = Self.sortItems(items, by: state.sortKey, order: state.sortOrder)
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
                state.lastSelectedId = nil
                state.rangeAnchorId = nil
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

            case let .selectByOffset(offset, isShiftPressed):
                guard !state.items.isEmpty else { return .none }

                guard let currentId = state.lastSelectedId,
                      let currentIndex = state.items.firstIndex(where: { $0.id == currentId })
                else {
                    if offset >= 0 {
                        guard let first = state.items.first else { return .none }
                        state.selectedIds = [first.id]
                        state.lastSelectedId = first.id
                    } else {
                        guard let last = state.items.last else { return .none }
                        state.selectedIds = [last.id]
                        state.lastSelectedId = last.id
                    }
                    state.rangeAnchorId = nil
                    return .none
                }

                let targetIndex = max(0, min(state.items.count - 1, currentIndex + offset))
                let targetItem = state.items[targetIndex]

                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? currentId
                    guard let anchorIndex = state.items.firstIndex(where: { $0.id == anchorId }) else { return .none }
                    let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                    state.selectedIds = Set(state.items[range].map { $0.id })
                    state.rangeAnchorId = anchorId
                } else {
                    state.selectedIds = [targetItem.id]
                    state.rangeAnchorId = nil
                }
                state.lastSelectedId = targetItem.id
                return .none

            case let .setSortKey(key):
                state.sortKey = key
                if !state.hasUserSetSortOrder {
                    state.sortOrder = state.defaultSortOrder
                }
                state.items = Self.sortItems(state.items, by: state.sortKey, order: state.sortOrder)
                return .none

            case let .setSortOrder(order):
                state.sortOrder = order
                state.hasUserSetSortOrder = true
                state.items = Self.sortItems(state.items, by: state.sortKey, order: state.sortOrder)
                return .none
            }
        }
    }
}

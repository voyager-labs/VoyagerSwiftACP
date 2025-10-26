import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

// swiftlint:disable type_body_length
/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    @ObservableState
    struct State: Equatable {
        var items: [FSItem] = []
        var selectedIds: Set<String> = []
        var lastSelectedId: String?
        var rangeAnchorId: String?
        var isLoading: Bool = false
        var showHiddenFiles: Bool = false
        var shouldScrollToSelection: Bool = false

        var sortKey: SortKey = .name
        var sortOrder: SortOrder = .ascending
        var hasUserSetSortOrder: Bool = false

        var groupKey: GroupKey = .none
        var groupedItems: [GroupedItems] = []

        var operations: FSItemsOperationsFeature.State = .init()

        var displayOrderItems: [FSItem] {
            if groupKey == .none {
                return items
            } else {
                return groupedItems.flatMap { $0.items }
            }
        }

        var defaultSortOrder: SortOrder {
            switch sortKey {
            case .dateModified, .dateCreated, .dateAdded, .dateLastOpened:
                return .descending
            case .name, .kind, .application, .size, .tags:
                return .ascending
            }
        }
    }

    enum Action: Sendable {
        case loadItems(path: String)
        case loadRecentItems
        case itemsLoaded([FSItem])
        case setShowHidden(Bool)
        case setGroupKey(GroupKey)
        case selectItem(id: String, isCommandPressed: Bool, isShiftPressed: Bool)
        case selectAll
        case clearSelection
        case selectNextItem(isShiftPressed: Bool)
        case selectPreviousItem(isShiftPressed: Bool)
        case selectByOffset(offset: Int, isShiftPressed: Bool)
        case resetScrollFlag

        case setSortKey(SortKey)
        case setSortOrder(SortOrder)

        case openSelectedItem
        case quickLookSelectedItem
        case openWithSelectedItem(bundleID: String?)
        case setDefaultAppForSelectedItem(bundleID: String, type: UTType?)
        case setDefaultAppWithOtherForSelectedItem
        case navigateFolder(id: String)
        case operations(FSItemsOperationsFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.operations, action: \.operations) {
            FSItemsOperationsFeature()
        }

        Reduce { state, action in
            switch action {
            case let .loadItems(path):
                state.isLoading = true
                let showHidden = state.showHiddenFiles
                return .run { [showHidden] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let loadItems: [FSItem] = FSItemsLoadUtils.loadItems(at: url, showHidden: showHidden)

                    await send(.itemsLoaded(loadItems))
                }

            case .loadRecentItems:
                state.isLoading = true
                return .run { send in
                    let recentItems = await SidebarUtils.loadRecentItems()
                    await send(.itemsLoaded(recentItems))
                }

            case let .setShowHidden(show):
                state.showHiddenFiles = show
                return .none

            case let .setGroupKey(key):
                state.groupKey = key
                state.groupedItems = FSItemsGrouping.groupItems(state.items, by: key)
                return .none

            case let .itemsLoaded(items):
                let sorted = FSItemsSorting.sortItems(items, by: state.sortKey, order: state.sortOrder)
                state.items = sorted
                state.groupedItems = FSItemsGrouping.groupItems(sorted, by: state.groupKey)
                state.isLoading = false
                return .none

            case let .selectItem(id, isCommandPressed, isShiftPressed):
                state.shouldScrollToSelection = false

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
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else {
                    return .none
                }

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
                            state.selectedIds = Set(displayItems[range].map { $0.id })
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
                return .none

            case let .selectPreviousItem(isShiftPressed):
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else {
                    return .none
                }

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
                            state.selectedIds = Set(displayItems[range].map { $0.id })
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
                return .none

            case let .selectByOffset(offset, isShiftPressed):
                let displayItems = state.displayOrderItems
                guard !displayItems.isEmpty else { return .none }

                guard let currentId = state.lastSelectedId,
                      let currentIndex = displayItems.firstIndex(where: { $0.id == currentId })
                else {
                    if offset >= 0 {
                        guard let first = displayItems.first else { return .none }
                        state.selectedIds = [first.id]
                        state.lastSelectedId = first.id
                    } else {
                        guard let last = displayItems.last else { return .none }
                        state.selectedIds = [last.id]
                        state.lastSelectedId = last.id
                    }
                    state.rangeAnchorId = nil
                    state.shouldScrollToSelection = true
                    return .none
                }

                let targetIndex = max(0, min(displayItems.count - 1, currentIndex + offset))
                let targetItem = displayItems[targetIndex]

                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? currentId
                    guard let anchorIndex = displayItems.firstIndex(where: { $0.id == anchorId }) else { return .none }
                    let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                    state.selectedIds = Set(displayItems[range].map { $0.id })
                    state.rangeAnchorId = anchorId
                } else {
                    state.selectedIds = [targetItem.id]
                    state.rangeAnchorId = nil
                }
                state.lastSelectedId = targetItem.id
                state.shouldScrollToSelection = true
                return .none

            case let .setSortKey(key):
                state.sortKey = key
                if !state.hasUserSetSortOrder {
                    state.sortOrder = state.defaultSortOrder
                }
                let sorted = FSItemsSorting.sortItems(state.items, by: state.sortKey, order: state.sortOrder)
                state.items = sorted
                state.groupedItems = FSItemsGrouping.groupItems(sorted, by: state.groupKey)
                return .none

            case let .setSortOrder(order):
                state.sortOrder = order
                state.hasUserSetSortOrder = true
                let sorted = FSItemsSorting.sortItems(state.items, by: state.sortKey, order: state.sortOrder)
                state.items = sorted
                state.groupedItems = FSItemsGrouping.groupItems(sorted, by: state.groupKey)
                return .none

            case .resetScrollFlag:
                state.shouldScrollToSelection = false
                return .none

            case .navigateFolder:
                return .none

            case .openSelectedItem:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                var selectedFolders: [FSItem] = []
                var selectedFiles: [FSItem] = []

                for selectedId in state.selectedIds {
                    if let item = state.items.first(where: { $0.id == selectedId }) {
                        if item.isDirectory {
                            selectedFolders.append(item)
                        } else {
                            selectedFiles.append(item)
                        }
                    }
                }

                if selectedFolders.count == 1 && selectedFiles.isEmpty {
                    return .send(.navigateFolder(id: selectedFolders[0].id))
                } else if selectedFolders.count > 1 && selectedFiles.isEmpty {
                    for folder in selectedFolders {
                        AppDelegate.shared?.createNewWindow(path: folder.fullPath)
                    }
                    return .none
                } else if !selectedFolders.isEmpty {
                    for folder in selectedFolders {
                        AppDelegate.shared?.createNewWindow(path: folder.fullPath)
                    }
                }

                guard !selectedFiles.isEmpty else {
                    return .none
                }

                return .send(.operations(.openFiles(files: selectedFiles)))

            case .quickLookSelectedItem:
                guard state.selectedIds.count == 1,
                      let selectedId = state.selectedIds.first,
                      let item = state.items.first(where: { $0.id == selectedId })
                else {
                    return .none
                }

                return .send(.operations(.quickLookFile(file: item)))

            case let .openWithSelectedItem(bundleID):
                guard state.selectedIds.count == 1,
                      let selectedId = state.selectedIds.first,
                      let item = state.items.first(where: { $0.id == selectedId }),
                      !item.isDirectory
                else {
                    return .none
                }

                if let bundleID = bundleID {
                    let filePath = item.fullPath
                    let url = URL(fileURLWithPath: filePath)
                    return .send(.operations(.openFileWithAppBundleID(
                        filePath: filePath,
                        bundleID: bundleID,
                        url: url
                    )))
                } else {
                    return .send(.operations(.openFileWithApp(file: item)))
                }

            case let .setDefaultAppForSelectedItem(bundleID, type):
                guard state.selectedIds.count == 1,
                      let selectedId = state.selectedIds.first,
                      let item = state.items.first(where: { $0.id == selectedId }),
                      !item.isDirectory
                else {
                    return .none
                }

                return .send(.operations(.setDefaultAppForFile(
                    type: type ?? UTType(filenameExtension: item.fileExtension),
                    bundleID: bundleID,
                    file: item
                )))

            case .setDefaultAppWithOtherForSelectedItem:
                guard state.selectedIds.count == 1,
                      let selectedId = state.selectedIds.first,
                      let item = state.items.first(where: { $0.id == selectedId }),
                      !item.isDirectory
                else {
                    return .none
                }

                return .send(.operations(.setDefaultAppWithOther(file: item)))

            case .operations:
                return .none
            }
        }
    }
}

// swiftlint:enable type_body_length

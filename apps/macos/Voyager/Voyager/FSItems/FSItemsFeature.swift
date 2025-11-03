// swiftlint:disable file_length
import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import UniformTypeIdentifiers

public enum ClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}

// swiftlint:disable type_body_length
/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    @ObservableState
    struct State: Equatable {
        var items: IdentifiedArrayOf<FSItem> = []
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

        var clipboardItems: [String] = []
        var clipboardOperation: ClipboardOperation = .copy

        var isDragDropOperation: Bool = false

        var renamingItemId: String?
        var renamingText: String = ""

        var isRenaming: Bool {
            renamingItemId != nil
        }

        var displayOrderItems: [FSItem] {
            if groupKey == .none {
                return Array(items)
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

        mutating func clearSelection() {
            selectedIds = []
            lastSelectedId = nil
            rangeAnchorId = nil
        }
    }

    enum Action: Sendable {
        case onAppear
        case reloadCurrentFolder
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
        case copySelectedItems
        case cutSelectedItems
        case pasteItems(destinationPath: String)
        case duplicateSelectedItems
        case startDrag(paths: [String])
        case dropToFolder(destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case startRename(id: String)
        case updateRenamingText(String)
        case commitRename
        case cancelRename
        case operations(FSItemsOperationsFeature.Action)
    }

    @Dependency(\.fileSystemClient)
    var fileSystemClient

    var body: some Reducer<State, Action> {
        Scope(state: \.operations, action: \.operations) {
            FSItemsOperationsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    for await _ in await fileSystemClient.observeFileSystemChanged() {
                        await send(.reloadCurrentFolder)
                    }
                }
                .cancellable(id: "FileSystemObserver", cancelInFlight: true)

            case .reloadCurrentFolder:
                let currentPath = state.items.first.map {
                    URL(fileURLWithPath: $0.fullPath).deletingLastPathComponent().path
                } ?? "/"
                return .send(.loadItems(path: currentPath))

            case let .operations(.operationFinished(filePath, kind, result)):
                if case .success = result {
                    if case .createFolder = kind {
                        return .run { _ in
                            await fileSystemClient.postFileSystemChanged([filePath])
                        }
                    } else if case .pasteFile = kind {
                        if state.isDragDropOperation {
                            state.isDragDropOperation = false
                        }

                        if state.clipboardOperation == .cut {
                            state.clipboardItems = []
                            state.clipboardOperation = .copy
                            fileSystemClient.saveClipboardPaths([], .copy)
                        }

                        return .run { _ in
                            await fileSystemClient.postFileSystemChanged([filePath])
                        }
                    } else if case .rename = kind {
                        return .run { _ in
                            await fileSystemClient.postFileSystemChanged([filePath])
                        }
                    }
                } else if case .pasteFile = kind {
                    if state.isDragDropOperation {
                        state.isDragDropOperation = false

                        let currentPath = state.items.first.map {
                            URL(fileURLWithPath: $0.fullPath).deletingLastPathComponent().path
                        } ?? "/"
                        return .send(.loadItems(path: currentPath))
                    }
                }
                return .none

            case .operations:
                return .none

            case let .loadItems(path):
                state.clearSelection()

                return .run { [showHidden = state.showHiddenFiles] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

                    do {
                        let items = try await fileSystemClient.loadItems(url, showHidden)
                        await send(.itemsLoaded(items))
                    } catch {
                        await send(.itemsLoaded([]))
                    }
                }

            case .loadRecentItems:
                return .run { send in
                    let recentItems = await SidebarUtils.loadRecentItems()
                    await send(.itemsLoaded(recentItems))
                }

            case let .setShowHidden(show):
                state.showHiddenFiles = show
                return .none

            case let .setGroupKey(key):
                state.groupKey = key
                state.groupedItems = FSItemsGrouping.groupItems(Array(state.items), by: key)
                return .none

            case let .itemsLoaded(items):
                let sorted = FSItemsSorting.sortItems(items, by: state.sortKey, order: state.sortOrder)
                state.items = IdentifiedArray(uniqueElements: sorted)
                state.groupedItems = FSItemsGrouping.groupItems(Array(state.items), by: state.groupKey)

                return .run { _ in
                    Task.detached(priority: .background) {
                        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
                        let baseSize: CGFloat = 64
                        let size = CGSize(width: baseSize * scale, height: baseSize * scale)

                        await ThumbnailGeneratorUtils.prefetchThumbnails(
                            for: Array(sorted),
                            size: size,
                            scale: scale
                        )
                    }
                }

            case let .selectItem(id, isCommandPressed, isShiftPressed):
                var renameEffect: Effect<Action> = .none

                if state.isRenaming {
                    renameEffect = .send(.commitRename)
                }

                state.shouldScrollToSelection = false

                if isShiftPressed {
                    guard let lastId = state.lastSelectedId,
                          let lastIndex = Array(state.items).firstIndex(where: { $0.id == lastId }),
                          let currentIndex = Array(state.items).firstIndex(where: { $0.id == id })
                    else {
                        state.selectedIds = [id]
                        state.lastSelectedId = id
                        state.rangeAnchorId = nil
                        return .merge(renameEffect, .none)
                    }

                    let itemsArray = Array(state.items)
                    let range = min(lastIndex, currentIndex) ... max(lastIndex, currentIndex)
                    let rangeIds = itemsArray[range].map { $0.id }
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
                return .merge(renameEffect, .none)

            case .selectAll:
                state.selectedIds = Set(state.items.map { $0.id })
                if let lastItem = state.items.last {
                    state.lastSelectedId = lastItem.id
                }
                return .none

            case .clearSelection:
                state.clearSelection()
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
                let sorted = FSItemsSorting.sortItems(Array(state.items), by: state.sortKey, order: state.sortOrder)
                state.items = IdentifiedArray(uniqueElements: sorted)
                state.groupedItems = FSItemsGrouping.groupItems(sorted, by: state.groupKey)
                return .none

            case let .setSortOrder(order):
                state.sortOrder = order
                state.hasUserSetSortOrder = true
                let sorted = FSItemsSorting.sortItems(Array(state.items), by: state.sortKey, order: state.sortOrder)
                state.items = IdentifiedArray(uniqueElements: sorted)
                state.groupedItems = FSItemsGrouping.groupItems(sorted, by: state.groupKey)
                return .none

            case .resetScrollFlag:
                state.shouldScrollToSelection = false
                return .none

            case let .navigateFolder(id):
                // 폴더 이동은 부모 Feature에서 처리
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

            case .copySelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = Array(state.items.filter { state.selectedIds.contains($0.id) })
                let selectedPaths = selectedItems.map { $0.fullPath }

                state.clipboardItems = selectedPaths
                state.clipboardOperation = .copy
                fileSystemClient.saveClipboardPaths(selectedPaths, .copy)

                return .send(.operations(.copySelectedItems(files: selectedItems)))

            case .cutSelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = Array(state.items.filter { state.selectedIds.contains($0.id) })
                let selectedPaths = selectedItems.map { $0.fullPath }

                state.clipboardItems = selectedPaths
                state.clipboardOperation = .cut
                fileSystemClient.saveClipboardPaths(selectedPaths, .cut)

                return .send(.operations(.copySelectedItems(files: selectedItems)))

            case let .pasteItems(destinationPath):
                let (clipboardPaths, clipboardOp) = fileSystemClient.loadClipboardPaths()
                guard !clipboardPaths.isEmpty else {
                    return .none
                }

                state.clipboardItems = clipboardPaths
                state.clipboardOperation = clipboardOp

                return .send(.operations(.pasteItems(
                    sourcePaths: clipboardPaths,
                    destinationPath: destinationPath,
                    operation: clipboardOp
                )))

            case .duplicateSelectedItems:
                let selectedItems = Array(state.items.filter { state.selectedIds.contains($0.id) })
                guard !selectedItems.isEmpty else {
                    return .none
                }

                let parentPath = URL(fileURLWithPath: selectedItems[0].fullPath)
                    .deletingLastPathComponent().path

                return .send(.operations(.pasteItems(
                    sourcePaths: selectedItems.map { $0.fullPath },
                    destinationPath: parentPath,
                    operation: .copy
                )))

            case let .startDrag(paths):
                fileSystemClient.saveDragPaths(paths)
                let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                fileSystemClient.saveDragWithOption(isOptionPressed)
                return .none

            case let .dropToFolder(destinationPath):
                let sourcePaths = fileSystemClient.loadDragPaths()
                let isOptionPressed = fileSystemClient.loadDragWithOption()
                guard !sourcePaths.isEmpty else {
                    return .none
                }
                return .send(.dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionPressed
                ))

            case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
                guard !sourcePaths.isEmpty else {
                    return .none
                }

                if !isOptionDrag {
                    let sourceParent = URL(fileURLWithPath: sourcePaths[0])
                        .deletingLastPathComponent().path
                    if sourceParent == destinationPath {
                        return .none
                    }

                    // 자기 자신의 하위 폴더로 이동 방지
                    for sourcePath in sourcePaths {
                        if destinationPath.hasPrefix(sourcePath + "/") || destinationPath == sourcePath {
                            return .none
                        }
                    }
                }

                // Drag & Drop 플래그 설정
                state.isDragDropOperation = true

                // Option 키에 따라 Copy 또는 Move
                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                return .send(.operations(.pasteItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    operation: operation
                )))

            case let .startRename(id):
                guard let item = state.items.first(where: { $0.id == id }) else {
                    return .none
                }

                state.renamingItemId = id
                state.renamingText = item.name

                return .none

            case let .updateRenamingText(text):
                state.renamingText = text
                return .none

            case .commitRename:
                guard let itemId = state.renamingItemId,
                      let item = state.items.first(where: { $0.id == itemId })
                else {
                    return .send(.cancelRename)
                }

                let trimmed = state.renamingText.trimmingCharacters(in: .whitespaces)

                guard !trimmed.isEmpty else {
                    return .send(.cancelRename)
                }

                let finalName = trimmed

                if finalName == item.name {
                    return .send(.cancelRename)
                }

                let oldPath = item.fullPath
                let parentPath = URL(fileURLWithPath: oldPath).deletingLastPathComponent()
                let newPath = parentPath.appendingPathComponent(finalName).path

                state.renamingItemId = nil
                state.renamingText = ""

                return .send(.operations(.renameItem(oldPath: oldPath, newPath: newPath)))

            case .cancelRename:
                state.renamingItemId = nil
                state.renamingText = ""
                return .none
            }
        }
    }
}

// swiftlint:enable type_body_length

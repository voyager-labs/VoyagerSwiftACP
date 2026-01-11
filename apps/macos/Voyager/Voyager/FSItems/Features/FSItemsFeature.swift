// swiftlint:disable file_length
import AppKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import OSLog
import UniformTypeIdentifiers

public enum ClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}

// swiftlint:disable type_body_length
/// 파일 시스템 아이템 목록 및 선택 관리 (FSV 영역)
@Reducer
struct FSItemsFeature {
    private static func deduplicateById(_ items: [FSItem]) -> [FSItem] {
        var seen: Set<String> = []
        var unique: [FSItem] = []
        unique.reserveCapacity(items.count)

        for item in items where seen.insert(item.id).inserted {
            unique.append(item)
        }

        return unique
    }

    private enum CancelID {
        static let fsEventsWatcher = "fsEventsWatcher"
    }

    // TODO: swift-log로 변경
    private nonisolated static let entryActionLogger = Logger(subsystem: "com.voyager", category: "entry-actions")

    enum EntryActionDirection: Sendable {
        case undo
        case redo
    }

    @ObservableState
    struct State: Equatable {
        var items: IdentifiedArrayOf<FSItem> = []
        var collectionItems: IdentifiedArrayOf<FSItem> = []
        var isCollectionMode: Bool = false
        var selectedIds: Set<String> = []
        var lastSelectedId: String?
        var rangeAnchorId: String?
        var isLoading: Bool = false
        var isReloading: Bool = false
        var showHiddenFiles: Bool = false
        var shouldScrollToSelection: Bool = false

        var sortKey: SortKey = .name
        var sortOrder: SortOrder = .ascending
        var hasUserSetSortOrder: Bool = false

        var groupKey: GroupKey = .none
        var groupedItems: [GroupedItems] = []

        var operations: FSItemsOperationsFeature.State = .init()
        var undoRecords: [EntryActionRecord] = []
        var redoRecords: [EntryActionRecord] = []

        var clipboardItems: [String] = []
        var clipboardOperation: ClipboardOperation = .copy

        var isDragDropOperation: Bool = false
        var isDropTargeted: Bool = false
        var draggingPaths: [String] = []

        var renamingItemId: String?
        var renamingText: String = ""
        var creatingNewFolderId: String?
        var creatingNewFolderPath: String?
        var creatingNewFolderOriginalName: String?
        var selectAfterLoadFileNames: [String] = []

        var isListView: Bool = true

        var currentFolderPath: String?
        var isVirtualFolder: Bool = false
        var thumbnailsReady: Set<String> = []

        var lassoSelection: LassoSelection?
        var listRowDragSelection: ListRowDragSelection?
        var itemPositions: [String: CGRect] = [:]
        var gridColumnCount: Int = 1

        var isRenaming: Bool {
            renamingItemId != nil
        }

        var displayItems: IdentifiedArrayOf<FSItem> {
            isCollectionMode ? collectionItems : items
        }

        var displayOrderItems: [FSItem] {
            if groupKey == .none {
                Array(displayItems)
            } else {
                groupedItems.flatMap(\.items)
            }
        }

        var defaultSortOrder: SortOrder {
            switch sortKey {
            case .dateModified, .dateCreated, .dateAdded, .dateLastOpened:
                .descending
            case .name, .kind, .application, .size, .tags:
                .ascending
            }
        }

        mutating func clearSelection() {
            selectedIds = []
            lastSelectedId = nil
            rangeAnchorId = nil
        }

        mutating func clearRenaming() {
            renamingItemId = nil
            renamingText = ""
        }

        mutating func clearCreatingFolder() {
            creatingNewFolderId = nil
            creatingNewFolderPath = nil
            creatingNewFolderOriginalName = nil
        }

        mutating func appendUndoRecord(_ record: EntryActionRecord) {
            undoRecords.append(record)
            redoRecords.removeAll()
        }

        var latestUndoRecord: EntryActionRecord? {
            undoRecords.last
        }

        var latestRedoRecord: EntryActionRecord? {
            redoRecords.last
        }

        var canUndoEntryAction: Bool {
            guard let record = latestUndoRecord else { return false }
            return !isEntryActionBusy(record)
        }

        var canRedoEntryAction: Bool {
            guard let record = latestRedoRecord else { return false }
            return !isEntryActionBusy(record)
        }

        func isEntryActionBusy(_ record: EntryActionRecord) -> Bool {
            let paths = record.targets
                .flatMap { [$0.beforePath, $0.afterPath] }
                .compactMap(\.self)
            return paths.contains { operations.itemStates[$0]?.isBusy == true }
        }
    }

    enum Action: Sendable {
        case onAppear
        case reloadCurrentFolder
        case loadItems(path: String)
        case reloadItems
        case loadRecentItems(showHidden: Bool)
        case loadTagItems(tagName: String, showHidden: Bool)
        case loadComputerItems
        case itemsLoaded([FSItem])
        case collectionItemsLoadedFromSearch([JSONValue])
        case fileSystemChanged([String])
        case setShowHidden(Bool)
        case setGroupKey(GroupKey)
        case setCollectionMode(Bool)
        case setDropTargeted(Bool)
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
        case openWithSelectedItem(bundleID: String?, shouldSetAsDefault: Bool)
        case openCollectionFile(URL)
        case navigateFolder(id: String)
        case copySelectedItems
        case cutSelectedItems
        case pasteItems(destinationPath: String)
        case duplicateSelectedItems
        case startDrag(paths: [String])
        case dropToFolder(destinationPath: String)
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case handleDropToTag(providers: [NSItemProvider], tagName: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case createNewFolder(currentPath: String)
        case confirmNewFolder(name: String, path: String, originalName: String)
        case moveSelectedItemsToTrash
        case deleteSelectedItemsImmediately
        case confirmDeleteImmediately(items: [FSItem])
        case putBackSelectedItems
        case compressSelectedItems
        case extractSelectedItem
        case toggleTagForSelectedItem(tag: String)
        case emptyTrash
        case setSelectAfterLoad(fileNames: [String])
        case thumbnailsReady(paths: [String])
        case startRename(id: String)
        case updateRenamingText(String)
        case commitRename
        case cancelRename

        case updateItemPositions([String: CGRect])
        case updateGridColumnCount(Int)
        case startLassoSelection(startPoint: CGPoint, modifierFlags: ModifierFlags)
        case updateLassoSelection(currentPoint: CGPoint)
        case endLassoSelection
        case cancelLassoSelection
        case startListRowDrag(startItemId: String, modifierFlags: ModifierFlags)
        case updateListRowDrag(currentItemId: String)
        case endListRowDrag
        case cancelListRowDrag

        case requestUndo
        case requestRedo
        case undoEntryAction(EntryActionRecord)
        case redoEntryAction(EntryActionRecord)
        case entryActionApplied(direction: EntryActionDirection, record: EntryActionRecord)
        case operations(FSItemsOperationsFeature.Action)
    }

    @Dependency(\.fsItemClient)
    var fsItemClient
    @Dependency(\.undoManagerClient)
    var undoManagerClient

    var body: some Reducer<State, Action> {
        Scope(state: \.operations, action: \.operations) {
            FSItemsOperationsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    for await _ in await fsItemClient.observeFileSystemChanged() {
                        await send(.reloadCurrentFolder)
                    }
                }
                .cancellable(id: "FileSystemObserver", cancelInFlight: true)

            case .reloadCurrentFolder:
                let (clipboardPaths, clipboardOp) = fsItemClient.loadClipboardPaths()
                state.clipboardItems = clipboardPaths
                state.clipboardOperation = clipboardOp

                if state.isVirtualFolder {
                    if state.currentFolderPath == SidebarUtils.computerName {
                        return .send(.loadComputerItems)
                    } else if let tagName = state.currentFolderPath {
                        return .send(.loadTagItems(tagName: tagName, showHidden: state.showHiddenFiles))
                    } else {
                        return .send(.loadRecentItems(showHidden: state.showHiddenFiles))
                    }
                } else {
                    return .send(.reloadItems)
                }

            case let .operations(.entryActionCompleted(record)):
                state.appendUndoRecord(record)

                return .run { [record] send in
                    await undoManagerClient.registerUndo(
                        record,
                        { record in
                            await send(.undoEntryAction(record))
                        },
                        { record in
                            await send(.redoEntryAction(record))
                        },
                    )
                }

            case .requestUndo:
                guard let record = state.latestUndoRecord else {
                    logClientError("Undo 불가: 기록 없음")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    logClientError("Undo 불가: 대상이 작업 중")
                    return .none
                }
                return .run { _ in
                    await undoManagerClient.undo()
                }

            case .requestRedo:
                guard let record = state.latestRedoRecord else {
                    logClientError("Redo 불가: 기록 없음")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    logClientError("Redo 불가: 대상이 작업 중")
                    return .none
                }
                return .run { _ in
                    await undoManagerClient.redo()
                }

            case let .operations(.operationFinished(filePath, kind, result)):
                switch (kind, result) {
                case (.createFolder, .success):
                    let isNewFolderFlow = !state.selectAfterLoadFileNames.isEmpty

                    return .merge(
                        .run { _ in
                            await fsItemClient.postFileSystemChanged([filePath])
                        },
                        {
                            if isNewFolderFlow, let currentPath = state.currentFolderPath {
                                return .send(.loadItems(path: currentPath))
                            }
                            return .none
                        }(),
                    )

                case (.pasteFile, .success):
                    if state.clipboardOperation == .cut {
                        state.clipboardItems = []
                        state.clipboardOperation = .copy

                        let pasteboard = NSPasteboard.general
                        pasteboard.setString(
                            "",
                            forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"),
                        )
                    }

                    if state.isDragDropOperation {
                        state.isDragDropOperation = false
                    }

                    return .merge(
                        .send(.reloadCurrentFolder),
                        .run { _ in
                            await fsItemClient.postFileSystemChanged([filePath])
                        },
                    )

                case (.rename, .success):
                    return .run { _ in
                        await fsItemClient.postFileSystemChanged([filePath])
                    }

                case (.moveToTrash, .success),
                     (.deleteImmediately, .success),
                     (.putBack, .success):
                    return .send(.reloadCurrentFolder)

                case (.compress, .success),
                     (.extract, .success),
                     (.setTags, .success):
                    return .send(.reloadCurrentFolder)

                case (.pasteFile, .failure):
                    if state.isDragDropOperation {
                        state.isDragDropOperation = false
                        return .send(.reloadCurrentFolder)
                    }
                    return .none

                default:
                    return .none
                }

            case let .undoEntryAction(record):
                guard let latestRecord = state.latestUndoRecord, latestRecord.id == record.id else {
                    logClientError("Undo 불가: 최신 기록 불일치")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    logClientError("Undo 불가: 대상이 작업 중")
                    return .none
                }
                _ = state.undoRecords.popLast()
                state.redoRecords.append(latestRecord)
                return applyEntryAction(latestRecord, direction: .undo)

            case let .redoEntryAction(record):
                guard let latestRecord = state.latestRedoRecord, latestRecord.id == record.id else {
                    logClientError("Redo 불가: 최신 기록 불일치")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    logClientError("Redo 불가: 대상이 작업 중")
                    return .none
                }
                _ = state.redoRecords.popLast()
                state.undoRecords.append(latestRecord)
                return applyEntryAction(latestRecord, direction: .redo)

            case let .entryActionApplied(direction, record):
                switch direction {
                case .undo:
                    guard let recordIndex = state.redoRecords.firstIndex(where: { $0.id == record.id }) else {
                        logClientError("Undo 불가: 스택 갱신 실패")
                        return .none
                    }
                    state.redoRecords[recordIndex] = record
                    return .none
                case .redo:
                    guard let recordIndex = state.undoRecords.firstIndex(where: { $0.id == record.id }) else {
                        logClientError("Redo 불가: 스택 갱신 실패")
                        return .none
                    }
                    state.undoRecords[recordIndex] = record
                    return .none
                }

            case .operations:
                return .none

            case let .loadItems(path):
                if state.selectAfterLoadFileNames.isEmpty {
                    state.clearSelection()
                }
                state.currentFolderPath = path
                state.isVirtualFolder = false

                return .merge(
                    .cancel(id: CancelID.fsEventsWatcher),

                    .run { [fsItemClient, showHidden = state.showHiddenFiles, path] send in
                        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

                        do {
                            let items = try await fsItemClient.loadItems(url, showHidden)
                            await send(.itemsLoaded(items))
                        } catch {
                            await send(.itemsLoaded([]))
                        }
                    },

                    .run { [fsItemClient, path] send in
                        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                        let stream = fsItemClient.startWatchingDirectory(url)

                        for await changedPaths in stream {
                            await send(.fileSystemChanged(changedPaths))
                        }
                    }
                    .cancellable(id: CancelID.fsEventsWatcher, cancelInFlight: true),
                )

            case .reloadItems:
                guard let path = state.currentFolderPath else { return .none }
                state.isReloading = true

                return .run { [fsItemClient, showHidden = state.showHiddenFiles, path] send in
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

                    do {
                        let items = try await fsItemClient.loadItems(url, showHidden)
                        await send(.itemsLoaded(items))
                    } catch {
                        await send(.itemsLoaded([]))
                    }
                }

            case let .loadRecentItems(showHidden):
                state.currentFolderPath = nil
                state.isVirtualFolder = true

                return .run { send in
                    let recentItems = await SidebarUtils.loadRecentItems(showHidden: showHidden)
                    await send(.itemsLoaded(recentItems))
                }

            case let .loadTagItems(tagName, showHidden):
                state.currentFolderPath = tagName
                state.isVirtualFolder = true

                return .run { send in
                    try await Task.sleep(for: .milliseconds(500))
                    let taggedItems = await SidebarUtils.loadFilesWithTag(tagName, showHidden: showHidden)
                    await send(.itemsLoaded(taggedItems))
                }

            case .loadComputerItems:
                state.currentFolderPath = SidebarUtils.computerName
                state.isVirtualFolder = true

                return .run { send in
                    let computerItems = try await fsItemClient.loadComputerItems()
                    await send(.itemsLoaded(computerItems))
                }

            case .fileSystemChanged:
                return .send(.reloadCurrentFolder)

            case let .setShowHidden(show):
                state.showHiddenFiles = show
                return .none

            case let .setGroupKey(key):
                state.groupKey = key
                state.groupedItems = FSItemsGroupingUtils.groupItems(Array(state.displayItems), by: key)
                return .none

            case let .setCollectionMode(isCollectionMode):
                guard state.isCollectionMode != isCollectionMode else { return .none }
                state.isCollectionMode = isCollectionMode
                state.clearSelection()
                state.operations.commonApplicationsForSelectedFiles = []
                state.groupedItems = FSItemsGroupingUtils.groupItems(Array(state.displayItems), by: state.groupKey)
                return .none

            case let .setDropTargeted(isTargeted):
                let draggedPaths = fsItemClient.loadDragPaths()

                if !draggedPaths.isEmpty, let currentFolder = state.currentFolderPath {
                    let sourceParent = URL(fileURLWithPath: draggedPaths[0]).deletingLastPathComponent().path
                    state.isDropTargeted = (sourceParent != currentFolder) && isTargeted
                } else {
                    state.isDropTargeted = isTargeted
                }
                return .none

            case let .itemsLoaded(items):
                let uniqueItems = Self.deduplicateById(items)
                let sorted = FSItemsSortingUtils.sortItems(uniqueItems, by: state.sortKey, order: state.sortOrder)
                state.items = IdentifiedArray(uniqueElements: sorted)

                guard !state.isCollectionMode else {
                    state.isReloading = false
                    return .none
                }

                state.groupedItems = FSItemsGroupingUtils.groupItems(sorted, by: state.groupKey)

                if !state.selectAfterLoadFileNames.isEmpty {
                    let fileNamesToSelect = state.selectAfterLoadFileNames
                    state.selectAfterLoadFileNames = []

                    let itemsToSelect = state.items.filter { fileNamesToSelect.contains($0.name) }
                    if !itemsToSelect.isEmpty {
                        state.selectedIds = Set(itemsToSelect.map(\.id))
                        state.lastSelectedId = itemsToSelect.first?.id
                        state.rangeAnchorId = nil
                        state.shouldScrollToSelection = true
                    }
                } else if state.isReloading {
                    let validIds = Set(state.items.map(\.id))
                    state.selectedIds = state.selectedIds.intersection(validIds)
                    state.isReloading = false
                } else {
                    state.clearSelection()
                }

                return generateThumbnailsEffect(for: sorted)

            case let .collectionItemsLoadedFromSearch(items):
                let converted = FSItemSearchUtils.convertCollectionItems(items, showHidden: state.showHiddenFiles)
                let uniqueItems = Self.deduplicateById(converted)
                let sorted = FSItemsSortingUtils.sortItems(uniqueItems, by: state.sortKey, order: state.sortOrder)
                state.collectionItems = IdentifiedArray(uniqueElements: sorted)

                guard state.isCollectionMode else {
                    return .none
                }

                state.groupedItems = FSItemsGroupingUtils.groupItems(sorted, by: state.groupKey)
                state.clearSelection()
                state.operations.commonApplicationsForSelectedFiles = []
                return generateThumbnailsEffect(for: sorted)

            case let .selectItem(id, isCommandPressed, isShiftPressed):
                var renameEffect: Effect<Action> = .none
                let displayItems = state.displayItems

                if state.isRenaming {
                    renameEffect = .send(.commitRename)
                }

                state.shouldScrollToSelection = false

                if isShiftPressed {
                    if state.isListView {
                        let anchorId = state.rangeAnchorId ?? state.lastSelectedId

                        if let anchorId,
                           let anchorIndex = Array(displayItems).firstIndex(where: { $0.id == anchorId }),
                           let currentIndex = Array(displayItems).firstIndex(where: { $0.id == id })
                        {
                            let itemsArray = Array(displayItems)
                            let range = min(anchorIndex, currentIndex) ... max(anchorIndex, currentIndex)
                            let rangeIds = itemsArray[range].map(\.id)
                            state.selectedIds.formUnion(rangeIds)
                            state.lastSelectedId = id
                        } else {
                            state.selectedIds.insert(id)
                            state.lastSelectedId = id

                            return .merge(
                                renameEffect,
                                preloadApplicationsEffect(
                                    selectedIds: state.selectedIds,
                                    items: displayItems,
                                    currentItemId: id,
                                ),
                            )
                        }
                    } else {
                        if state.selectedIds.contains(id) {
                            state.selectedIds.remove(id)
                        } else {
                            state.selectedIds.insert(id)
                            state.lastSelectedId = id
                        }
                        state.rangeAnchorId = nil
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
                    preloadApplicationsEffect(selectedIds: state.selectedIds, items: displayItems, currentItemId: id),
                )

            case .selectAll:
                state.selectedIds = Set(state.displayItems.map(\.id))
                if let lastItem = state.displayItems.last {
                    state.lastSelectedId = lastItem.id
                }

                return preloadApplicationsEffect(selectedIds: state.selectedIds, items: state.displayItems)

            case .clearSelection:
                state.clearSelection()
                state.operations.commonApplicationsForSelectedFiles = []
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
                return preloadApplicationsEffect(selectedIds: state.selectedIds, items: state.displayItems)

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
                return preloadApplicationsEffect(selectedIds: state.selectedIds, items: state.displayItems)

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
                    return preloadApplicationsEffect(
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
                return preloadApplicationsEffect(selectedIds: state.selectedIds, items: state.displayItems)

            case let .setSortKey(key):
                state.sortKey = key
                if !state.hasUserSetSortOrder {
                    state.sortOrder = state.defaultSortOrder
                }
                let sortedItems = FSItemsSortingUtils.sortItems(
                    Array(state.items),
                    by: state.sortKey,
                    order: state.sortOrder,
                )
                state.items = IdentifiedArray(uniqueElements: sortedItems)
                let sortedCollection = FSItemsSortingUtils.sortItems(
                    Array(state.collectionItems),
                    by: state.sortKey,
                    order: state.sortOrder,
                )
                state.collectionItems = IdentifiedArray(uniqueElements: sortedCollection)
                state.groupedItems = FSItemsGroupingUtils.groupItems(Array(state.displayItems), by: state.groupKey)
                return .none

            case let .setSortOrder(order):
                state.sortOrder = order
                state.hasUserSetSortOrder = true
                let sortedItems = FSItemsSortingUtils.sortItems(
                    Array(state.items),
                    by: state.sortKey,
                    order: state.sortOrder,
                )
                state.items = IdentifiedArray(uniqueElements: sortedItems)
                let sortedCollection = FSItemsSortingUtils.sortItems(
                    Array(state.collectionItems),
                    by: state.sortKey,
                    order: state.sortOrder,
                )
                state.collectionItems = IdentifiedArray(uniqueElements: sortedCollection)
                state.groupedItems = FSItemsGroupingUtils.groupItems(Array(state.displayItems), by: state.groupKey)
                return .none

            case .resetScrollFlag:
                state.shouldScrollToSelection = false
                return .none

            case .navigateFolder:
                // 폴더 이동은 부모 Feature에서 처리
                return .none

            case .openCollectionFile:
                // 콜렉션 파일 열기는 부모 Feature에서 처리
                return .none

            case .openSelectedItem:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                let selectedCollections = selectedItems.filter {
                    $0.fileExtension.lowercased() == "voycoll"
                }
                if !selectedCollections.isEmpty, selectedCollections.count == selectedItems.count {
                    if selectedCollections.count == 1, let item = selectedCollections.first {
                        return .send(.openCollectionFile(URL(fileURLWithPath: item.fullPath)))
                    }
                    return .concatenate(selectedCollections.map {
                        .send(.openCollectionFile(URL(fileURLWithPath: $0.fullPath)))
                    })
                }
                let selectedPackages = selectedItems.filter { isPackageItem($0) }
                let selectedFolders = selectedItems.filter { $0.isDirectory && !isPackageItem($0) }
                let selectedFiles = selectedItems.filter { !$0.isDirectory } + selectedPackages

                if selectedFolders.count == 1, selectedFiles.isEmpty {
                    return .send(.navigateFolder(id: selectedFolders[0].id))
                } else if selectedFolders.count > 1, selectedFiles.isEmpty {
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

                if selectedFolders.isEmpty,
                   selectedFiles.count == 1,
                   let file = selectedFiles.first,
                   URL(fileURLWithPath: file.fullPath).pathExtension.lowercased() == "voycoll"
                {
                    return .send(.openCollectionFile(URL(fileURLWithPath: file.fullPath)))
                }

                return .send(.operations(.openFiles(files: selectedFiles)))

            case .quickLookSelectedItem:
                guard state.selectedIds.count == 1,
                      let selectedId = state.selectedIds.first,
                      let item = state.displayItems.first(where: { $0.id == selectedId })
                else {
                    return .none
                }

                return .send(.operations(.quickLookFile(file: item)))

            case let .openWithSelectedItem(bundleID, shouldSetAsDefault):
                let selectedFiles = getSelectedFiles(selectedIds: state.selectedIds, items: state.displayItems)

                guard !selectedFiles.isEmpty else {
                    return .none
                }

                if selectedFiles.count == 1 {
                    guard let item = selectedFiles.first else { return .none }

                    if let bundleID {
                        let filePath = item.fullPath
                        let url = URL(fileURLWithPath: filePath)
                        let fileType = UTType(filenameExtension: item.fileExtension)

                        var effects: [Effect<Action>] = []

                        if shouldSetAsDefault, let fileType {
                            effects.append(.send(.operations(.setDefaultAppForFile(
                                type: fileType,
                                bundleID: bundleID,
                                file: item,
                            ))))
                        }

                        effects.append(.send(.operations(.openFileWithAppBundleID(
                            filePath: filePath,
                            bundleID: bundleID,
                            url: url,
                        ))))

                        return .concatenate(effects)
                    } else {
                        if shouldSetAsDefault {
                            return .send(.operations(.setDefaultAppWithOther(file: item)))
                        } else {
                            return .send(.operations(.openFileWithApp(file: item)))
                        }
                    }
                } else {
                    if let bundleID {
                        var effects: [Effect<Action>] = []

                        for file in selectedFiles {
                            let filePath = file.fullPath
                            let url = URL(fileURLWithPath: filePath)
                            let fileType = UTType(filenameExtension: file.fileExtension)

                            if shouldSetAsDefault, let fileType {
                                effects.append(.send(.operations(.setDefaultAppForFile(
                                    type: fileType,
                                    bundleID: bundleID,
                                    file: file,
                                ))))
                            }

                            effects.append(.send(.operations(.openFileWithAppBundleID(
                                filePath: filePath,
                                bundleID: bundleID,
                                url: url,
                            ))))
                        }

                        return .concatenate(effects)
                    } else {
                        return .send(.operations(.openFilesWithAppFromOther(
                            files: selectedFiles,
                            shouldSetAsDefault: shouldSetAsDefault,
                        )))
                    }
                }

            case .copySelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                let selectedPaths = selectedItems.map(\.fullPath)

                state.clipboardItems = selectedPaths
                state.clipboardOperation = .copy

                return .run { [fsItemClient] send in
                    await send(.operations(.copySelectedItems(files: selectedItems)))

                    fsItemClient.postFileSystemChanged([])
                }

            case .cutSelectedItems:
                guard !state.selectedIds.isEmpty else {
                    return .none
                }

                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                let selectedPaths = selectedItems.map(\.fullPath)

                state.clipboardItems = selectedPaths
                state.clipboardOperation = .cut

                return .run { [fsItemClient] send in
                    await send(.operations(.copySelectedItems(files: selectedItems)))

                    let pasteboard = NSPasteboard.general
                    pasteboard.setString("cut", forType: NSPasteboard.PasteboardType("com.voyager.clipboard.operation"))

                    fsItemClient.postFileSystemChanged([])
                }

            case let .pasteItems(destinationPath):
                let (clipboardPaths, clipboardOp) = fsItemClient.loadClipboardPaths()
                guard !clipboardPaths.isEmpty else {
                    return .none
                }

                state.clipboardItems = clipboardPaths
                state.clipboardOperation = clipboardOp
                let actionKind: EntryActionRecord.ActionKind = clipboardOp == .cut ? .move : .paste

                return .send(.operations(.pasteItems(
                    sourcePaths: clipboardPaths,
                    destinationPath: destinationPath,
                    operation: clipboardOp,
                    actionKind: actionKind,
                )))

            case .duplicateSelectedItems:
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else {
                    return .none
                }

                let parentPath = URL(fileURLWithPath: selectedItems[0].fullPath)
                    .deletingLastPathComponent().path

                return .send(.operations(.pasteItems(
                    sourcePaths: selectedItems.map(\.fullPath),
                    destinationPath: parentPath,
                    operation: .copy,
                    actionKind: .duplicate,
                )))

            case let .startDrag(paths):
                state.draggingPaths = paths
                fsItemClient.saveDragPaths(paths)
                let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                fsItemClient.saveDragWithOption(isOptionPressed)
                return .none

            case let .handleDrop(providers, destinationPath):
                let draggedPaths = fsItemClient.loadDragPaths()
                let hasExternalProviders = !providers.isEmpty

                if !draggedPaths.isEmpty, !hasExternalProviders {
                    state.draggingPaths = []
                    return .send(.dropToFolder(destinationPath: destinationPath))
                }

                state.draggingPaths = []
                fsItemClient.saveDragPaths([])

                return .run { @MainActor send in
                    var urls: [URL] = []
                    for provider in providers
                        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    {
                        let result: URL? = await withCheckedContinuation { continuation in
                            provider
                                .loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                    var url: URL?
                                    if let urlItem = item as? URL {
                                        url = urlItem
                                    } else if let data = item as? Data {
                                        url = URL(dataRepresentation: data, relativeTo: nil)
                                    }
                                    continuation.resume(returning: url)
                                }
                        }
                        if let url = result {
                            urls.append(url)
                        }
                    }

                    if !urls.isEmpty {
                        let paths = urls.map(\.path)
                        let isOption = NSEvent.modifierFlags.contains(.option)
                        await send(.dropItems(
                            sourcePaths: paths,
                            destinationPath: destinationPath,
                            isOptionDrag: isOption,
                        ))
                    }
                }

            case let .handleDropToTag(providers, tagName):
                return .run { @MainActor [fsItemClient] _ in
                    var urls: [URL] = []
                    for provider in providers
                        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    {
                        let result: URL? = await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                var url: URL?
                                if let urlItem = item as? URL {
                                    url = urlItem
                                } else if let data = item as? Data {
                                    url = URL(dataRepresentation: data, relativeTo: nil)
                                }
                                continuation.resume(returning: url)
                            }
                        }
                        if let url = result {
                            urls.append(url)
                        }
                    }

                    for url in urls {
                        let currentTags = await (try? fsItemClient.getTags(url)) ?? []
                        if !currentTags.contains(tagName) {
                            try? await fsItemClient.toggleTag(url, tagName)
                        }
                    }
                }

            case let .dropToFolder(destinationPath):
                let sourcePaths = fsItemClient.loadDragPaths()
                let isOptionPressed = fsItemClient.loadDragWithOption()

                fsItemClient.saveDragPaths([])

                guard !sourcePaths.isEmpty else {
                    return .none
                }
                return .send(.dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionPressed,
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

                if destinationPath == state.currentFolderPath {
                    let fileNames = sourcePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
                    state.selectAfterLoadFileNames = fileNames
                }

                // Option 키에 따라 Copy 또는 Move
                let operation: ClipboardOperation = isOptionDrag ? .copy : .cut
                let actionKind: EntryActionRecord.ActionKind = isOptionDrag ? .paste : .move

                return .merge(
                    .send(.operations(.pasteItems(
                        sourcePaths: sourcePaths,
                        destinationPath: destinationPath,
                        operation: operation,
                        actionKind: actionKind,
                    ))),

                    // 윈도우 포커싱 (destinationPath의 윈도우 찾기)
                    .run { [destinationPath] _ in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await MainActor.run {
                            guard let appDelegate = AppDelegate.shared else { return }

                            // destinationPath에 해당하는 윈도우 찾기
                            let targetController = appDelegate.windowControllers.first { controller in
                                controller.store.currentPath == destinationPath
                            }

                            targetController?.window?.makeKeyAndOrderFront(nil)
                        }
                    },
                )

            case let .startRename(id):
                guard let item = state.displayItems.first(where: { $0.id == id }) else {
                    return .none
                }

                state.renamingItemId = id
                state.renamingText = item.name

                return .none

            case let .updateRenamingText(text):
                state.renamingText = text
                return .none

            case let .createNewFolder(currentPath):
                var folderName = "untitled folder"
                var counter = 2
                while state.items.contains(where: { $0.name == folderName }) {
                    folderName = "untitled folder \(counter)"
                    counter += 1
                }

                let tempId = "temp-\(UUID().uuidString)"
                let tempItem = FSItem.temporaryFolder(id: tempId, name: folderName)

                state.items.insert(tempItem, at: 0)
                state.creatingNewFolderId = tempId
                state.creatingNewFolderPath = currentPath
                state.creatingNewFolderOriginalName = folderName
                state.renamingItemId = tempId
                state.renamingText = folderName
                state.shouldScrollToSelection = true

                return .none

            case let .confirmNewFolder(name, path, originalName):
                return .run { send in
                    let parentURL = URL(fileURLWithPath: path)
                    let targetPath = parentURL.appendingPathComponent(name).path

                    let folderName: String
                    if FileManager.default.fileExists(atPath: targetPath) {
                        await MainActor.run {
                            FSItemAlertUtils.showRenameConflictAlert(itemName: name)
                        }
                        folderName = originalName
                    } else {
                        folderName = name
                    }

                    await send(.setSelectAfterLoad(fileNames: [folderName]))
                    await send(.operations(.createNewFolder(name: folderName, parentPath: path)))
                }

            case .moveSelectedItemsToTrash:
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else { return .none }

                return .send(.operations(.moveToTrash(items: selectedItems)))

            case .deleteSelectedItemsImmediately:
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else { return .none }

                return .run { send in
                    let itemNames = selectedItems.map(\.name)
                    let confirmed = await FSItemAlertUtils.showDeleteConfirmationAlert(itemNames: itemNames)

                    if confirmed {
                        await send(.confirmDeleteImmediately(items: selectedItems))
                    }
                }

            case let .confirmDeleteImmediately(items):
                return .send(.operations(.deleteImmediately(items: items)))

            case .putBackSelectedItems:
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else { return .none }

                return .send(.operations(.putBackFromTrash(items: selectedItems)))

            case .compressSelectedItems:
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else { return .none }

                return .send(.operations(.compressItems(items: selectedItems)))

            case .extractSelectedItem:
                guard let selectedItem = state.displayItems.first(where: { state.selectedIds.contains($0.id) }),
                      selectedItem.fileExtension.lowercased() == "zip"
                else { return .none }

                return .send(.operations(.extractCompressedFile(file: selectedItem)))

            case let .toggleTagForSelectedItem(tag):
                let selectedItems = getSelectedItems(selectedIds: state.selectedIds, items: state.displayItems)
                guard !selectedItems.isEmpty else { return .none }

                let targets = selectedItems.map { item in
                    let beforeTags = (item.tags ?? []).map(\.name)
                    let afterTags: [String] = if beforeTags.contains(tag) {
                        beforeTags.filter { $0 != tag }
                    } else {
                        beforeTags + [tag]
                    }

                    return FSItemsOperationsFeature.TagChangeTarget(
                        file: item,
                        beforeTags: beforeTags,
                        afterTags: afterTags,
                    )
                }

                return .send(.operations(.setTagsForItems(targets: targets)))

            case .emptyTrash:
                let allItems = Array(state.items)
                return .run { send in
                    let shouldEmpty = await FSItemAlertUtils.showEmptyTrashConfirmationAlert(itemCount: allItems.count)
                    guard shouldEmpty else { return }
                    await send(.operations(.emptyTrash(items: allItems)))
                }

            case let .setSelectAfterLoad(fileNames):
                state.selectAfterLoadFileNames = fileNames
                return .none

            case let .thumbnailsReady(paths):
                state.thumbnailsReady.formUnion(paths)
                return .none

            case .commitRename:
                guard let itemId = state.renamingItemId,
                      let item = state.displayItems.first(where: { $0.id == itemId })
                else {
                    return .send(.cancelRename)
                }

                let trimmed = state.renamingText.trimmingCharacters(in: .whitespaces)

                guard !trimmed.isEmpty else {
                    return .send(.cancelRename)
                }

                let finalName = trimmed

                if let creatingId = state.creatingNewFolderId,
                   creatingId == itemId,
                   let parentPath = state.creatingNewFolderPath,
                   let originalName = state.creatingNewFolderOriginalName
                {
                    state.clearRenaming()
                    state.clearCreatingFolder()
                    state.items.remove(id: itemId)

                    return .send(.confirmNewFolder(name: finalName, path: parentPath, originalName: originalName))
                }

                if finalName == item.name {
                    return .send(.cancelRename)
                }

                let oldPath = item.fullPath
                let parentPath = URL(fileURLWithPath: oldPath).deletingLastPathComponent()
                let newPath = parentPath.appendingPathComponent(finalName).path

                state.clearRenaming()
                state.selectAfterLoadFileNames = [finalName]

                return .send(.operations(.renameItem(oldPath: oldPath, newPath: newPath)))

            case .cancelRename:
                if let creatingId = state.creatingNewFolderId, creatingId == state.renamingItemId {
                    state.items.remove(id: creatingId)
                    state.clearCreatingFolder()
                }

                state.clearRenaming()
                return .none

            case let .updateItemPositions(positions):
                state.itemPositions = positions
                return .none

            case let .updateGridColumnCount(count):
                state.gridColumnCount = count
                return .none

            case let .startLassoSelection(startPoint, modifierFlags):
                state.lassoSelection = LassoSelection(
                    startPoint: startPoint,
                    currentPoint: startPoint,
                    initialSelectedIds: modifierFlags == .none ? [] : state.selectedIds,
                    modifierFlags: modifierFlags,
                )
                return .none

            case let .updateLassoSelection(currentPoint):
                guard var lasso = state.lassoSelection else { return .none }
                lasso.currentPoint = currentPoint

                let itemsInLasso = LassoSelectionUtils.calculateItemsInRect(
                    lasso.rect,
                    items: state.displayItems,
                    itemPositions: state.itemPositions,
                )

                // Modifier에 따라 최종 선택 계산
                state.selectedIds = LassoSelectionUtils.calculateFinalSelection(
                    itemsInLasso: itemsInLasso,
                    initialSelected: lasso.initialSelectedIds,
                    modifierFlags: lasso.modifierFlags,
                )

                if !state.selectedIds.isEmpty {
                    if let lastItem = state.displayOrderItems.last(where: { state.selectedIds.contains($0.id) }) {
                        state.lastSelectedId = lastItem.id
                    }
                }

                state.lassoSelection = lasso
                return .none

            case .endLassoSelection:
                if !state.selectedIds.isEmpty {
                    if let lastItem = state.displayOrderItems.last(where: { state.selectedIds.contains($0.id) }) {
                        state.lastSelectedId = lastItem.id
                        state.rangeAnchorId = nil
                    }
                }

                state.lassoSelection = nil
                return .none

            case .cancelLassoSelection:
                if let lasso = state.lassoSelection {
                    state.selectedIds = lasso.initialSelectedIds

                    if !lasso.initialSelectedIds.isEmpty {
                        if let lastItem = state.displayOrderItems
                            .last(where: { lasso.initialSelectedIds.contains($0.id) })
                        {
                            state.lastSelectedId = lastItem.id
                        }
                    }
                    state.rangeAnchorId = nil
                }
                state.lassoSelection = nil
                return .none

            case let .startListRowDrag(startItemId, modifierFlags):
                state.listRowDragSelection = ListRowDragSelection(
                    startItemId: startItemId,
                    currentItemId: startItemId,
                    initialSelectedIds: modifierFlags == .none ? [] : state.selectedIds,
                    modifierFlags: modifierFlags,
                )
                return .none

            case let .updateListRowDrag(currentItemId):
                guard var drag = state.listRowDragSelection else { return .none }
                drag.currentItemId = currentItemId
                state.listRowDragSelection = drag

                let displayItems = state.displayOrderItems
                guard let startIndex = displayItems.firstIndex(where: { $0.id == drag.startItemId }),
                      let currentIndex = displayItems.firstIndex(where: { $0.id == currentItemId })
                else { return .none }

                let range = min(startIndex, currentIndex) ... max(startIndex, currentIndex)
                let rangeIds = Set(displayItems[range].map(\.id))

                switch drag.modifierFlags {
                case .none:
                    state.selectedIds = rangeIds
                case .shift:
                    state.selectedIds = drag.initialSelectedIds.union(rangeIds)
                case .command:
                    state.selectedIds = drag.initialSelectedIds.symmetricDifference(rangeIds)
                }
                return .none

            case .endListRowDrag:
                if let drag = state.listRowDragSelection, !state.selectedIds.isEmpty {
                    state.lastSelectedId = drag.currentItemId
                    state.rangeAnchorId = drag.currentItemId
                }
                state.listRowDragSelection = nil
                return .none

            case .cancelListRowDrag:
                if let drag = state.listRowDragSelection {
                    state.selectedIds = drag.initialSelectedIds
                    if !drag.initialSelectedIds.isEmpty {
                        if let lastItem = state.displayOrderItems
                            .last(where: { drag.initialSelectedIds.contains($0.id) })
                        {
                            state.lastSelectedId = lastItem.id
                        }
                    }
                    state.rangeAnchorId = nil
                }
                state.listRowDragSelection = nil
                return .none
            }
        }
    }

    private struct EntryActionOperation {
        let operationPath: String
        let operationKind: OperationKind
        let perform: @Sendable () async throws -> EntryActionRecord.Target
    }

    private func logClientError(_ message: String) {
        Self.entryActionLogger.info("ClientError: \(message, privacy: .public)")
    }

    private func applyEntryAction(
        _ record: EntryActionRecord,
        direction: EntryActionDirection,
    ) -> Effect<Action> {
        let fsItemClient = fsItemClient

        return .run { send in
            do {
                let targets = try await applyEntryActionTargets(
                    record: record,
                    direction: direction,
                    fsItemClient: fsItemClient,
                    send: send,
                )
                let updatedRecord = EntryActionRecord(
                    actionKind: record.actionKind,
                    targets: targets,
                    id: record.id,
                    timestamp: record.timestamp,
                )
                await send(.entryActionApplied(direction: direction, record: updatedRecord))
            } catch {
                let message = (error as? FileOpError)?.message ?? error.localizedDescription
                Self.entryActionLogger.info(
                    "ClientError: \(String(describing: direction)) 실패 - \(message, privacy: .public)",
                )
            }
        }
    }

    private func applyEntryActionTargets(
        record: EntryActionRecord,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
        send: Send<Action>,
    ) async throws -> [EntryActionRecord.Target] {
        guard !record.targets.isEmpty else {
            throw FileOpError.system(message: "Entry action targets missing")
        }

        var updatedTargets: [EntryActionRecord.Target] = []

        for target in record.targets {
            let operation = try makeEntryActionOperation(
                record: record,
                target: target,
                direction: direction,
                fsItemClient: fsItemClient,
            )

            await send(.operations(.operationStarted(operation.operationPath, operation.operationKind)))
            do {
                let updatedTarget = try await operation.perform()
                await send(.operations(.operationFinished(
                    operation.operationPath,
                    operation.operationKind,
                    .success(()),
                )))
                updatedTargets.append(updatedTarget)
            } catch {
                let fileError = error.fileOpError
                await send(.operations(.operationFinished(
                    operation.operationPath,
                    operation.operationKind,
                    .failure(fileError),
                )))
                throw fileError
            }
        }

        return updatedTargets
    }

    private func makeEntryActionOperation(
        record: EntryActionRecord,
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        switch record.actionKind {
        case .rename:
            try makeRenameOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .move:
            try makeMoveOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .paste, .duplicate:
            try makeCopyOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .createFolder:
            try makeCreateFolderOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .moveToTrash:
            try makeMoveToTrashOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .putBack:
            try makePutBackOperation(target: target, direction: direction, fsItemClient: fsItemClient)

        case .setTags:
            try makeSetTagsOperation(target: target, direction: direction, fsItemClient: fsItemClient)
        }
    }

    private func makeRenameOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        let fromPath = try Self.requiredPath(
            direction == .undo ? target.afterPath : target.beforePath,
            context: "rename source",
        )
        let toPath = try Self.requiredPath(
            direction == .undo ? target.beforePath : target.afterPath,
            context: "rename destination",
        )
        return EntryActionOperation(
            operationPath: fromPath,
            operationKind: .rename,
            perform: {
                try await fsItemClient.renameFile(
                    URL(fileURLWithPath: fromPath),
                    URL(fileURLWithPath: toPath),
                )
                return target
            },
        )
    }

    private func makeMoveOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        let fromPath = try Self.requiredPath(
            direction == .undo ? target.afterPath : target.beforePath,
            context: "move source",
        )
        let toPath = try Self.requiredPath(
            direction == .undo ? target.beforePath : target.afterPath,
            context: "move destination",
        )
        return EntryActionOperation(
            operationPath: fromPath,
            operationKind: .pasteFile,
            perform: {
                try await fsItemClient.moveFile(
                    URL(fileURLWithPath: fromPath),
                    URL(fileURLWithPath: toPath),
                )
                return target
            },
        )
    }

    private func makeCopyOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "undo copy target")
            return EntryActionOperation(
                operationPath: targetPath,
                operationKind: .deleteImmediately,
                perform: {
                    try await fsItemClient.deleteImmediately(URL(fileURLWithPath: targetPath))
                    return target
                },
            )
        case .redo:
            let sourcePath = try Self.requiredPath(target.beforePath, context: "redo copy source")
            let targetPath = try Self.requiredPath(target.afterPath, context: "redo copy target")
            return EntryActionOperation(
                operationPath: sourcePath,
                operationKind: .pasteFile,
                perform: {
                    try await fsItemClient.pasteFile(
                        URL(fileURLWithPath: sourcePath),
                        URL(fileURLWithPath: targetPath),
                    )
                    return target
                },
            )
        }
    }

    private func makeCreateFolderOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "undo create folder")
            return EntryActionOperation(
                operationPath: targetPath,
                operationKind: .deleteImmediately,
                perform: {
                    try await fsItemClient.deleteImmediately(URL(fileURLWithPath: targetPath))
                    return target
                },
            )
        case .redo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "redo create folder")
            let targetURL = URL(fileURLWithPath: targetPath)
            let parentURL = targetURL.deletingLastPathComponent()
            let folderName = targetURL.lastPathComponent
            return EntryActionOperation(
                operationPath: parentURL.path,
                operationKind: .createFolder,
                perform: {
                    try await fsItemClient.createFolder(parentURL, folderName)
                    return target
                },
            )
        }
    }

    private func makeMoveToTrashOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let trashPath = try Self.requiredPath(target.afterPath, context: "undo moveToTrash source")
            let originalPath = try Self.requiredPath(target.beforePath, context: "undo moveToTrash destination")
            return EntryActionOperation(
                operationPath: trashPath,
                operationKind: .putBack,
                perform: {
                    try await fsItemClient.putBackFromTrash(
                        URL(fileURLWithPath: trashPath),
                        originalPath,
                    )
                    return target
                },
            )
        case .redo:
            let originalPath = try Self.requiredPath(target.beforePath, context: "redo moveToTrash source")
            return EntryActionOperation(
                operationPath: originalPath,
                operationKind: .moveToTrash,
                perform: {
                    let trashPath = try await Self.moveItemToTrash(path: originalPath)
                    return EntryActionRecord.Target(beforePath: originalPath, afterPath: trashPath)
                },
            )
        }
    }

    private func makePutBackOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let originalPath = try Self.requiredPath(target.afterPath, context: "undo putBack source")
            return EntryActionOperation(
                operationPath: originalPath,
                operationKind: .moveToTrash,
                perform: {
                    let trashPath = try await Self.moveItemToTrash(path: originalPath)
                    return EntryActionRecord.Target(beforePath: trashPath, afterPath: originalPath)
                },
            )
        case .redo:
            let trashPath = try Self.requiredPath(target.beforePath, context: "redo putBack source")
            let originalPath = try Self.requiredPath(target.afterPath, context: "redo putBack destination")
            return EntryActionOperation(
                operationPath: trashPath,
                operationKind: .putBack,
                perform: {
                    try await fsItemClient.putBackFromTrash(
                        URL(fileURLWithPath: trashPath),
                        originalPath,
                    )
                    return target
                },
            )
        }
    }

    private func makeSetTagsOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        fsItemClient: FSItemClient,
    ) throws -> EntryActionOperation {
        let filePath = try Self.requiredPath(target.beforePath, context: "setTags target")
        let tags = try Self.requiredTags(
            direction == .undo ? target.beforeTags : target.afterTags,
            context: "setTags tags",
        )
        return EntryActionOperation(
            operationPath: filePath,
            operationKind: .setTags,
            perform: {
                let url = URL(fileURLWithPath: filePath)
                try await fsItemClient.setTags(url, tags)
                return target
            },
        )
    }

    private static func requiredPath(_ path: String?, context: String) throws -> String {
        guard let path else {
            throw FileOpError.system(message: "Entry action path missing (\(context))")
        }
        return path
    }

    private static func requiredTags(_ tags: [String]?, context: String) throws -> [String] {
        guard let tags else {
            throw FileOpError.system(message: "Entry action tags missing (\(context))")
        }
        return tags
    }

    private static func moveItemToTrash(path: String) async throws -> String {
        let sourceURL = URL(fileURLWithPath: path)
        let trashURL = try await MainActor.run {
            var result: NSURL?
            try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &result)
            guard let trashURL = result as URL? else {
                throw FileOpError.system(message: "Trash URL not found")
            }
            return trashURL
        }
        let metadata = TrashMetadata(
            trashPath: trashURL.path,
            originalPath: path,
            deletedDate: Date(),
        )
        await TrashMetadataStore.shared.save(metadata)
        return trashURL.path
    }

    private func generateThumbnailsEffect(for items: [FSItem]) -> Effect<Action> {
        .run { send in
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
            let baseSize: CGFloat = 64
            let size = CGSize(width: baseSize * scale, height: baseSize * scale)

            await withTaskGroup(of: String?.self) { group in
                for item in items {
                    group.addTask {
                        let canGenerate = await MainActor.run {
                            ThumbnailGeneratorUtils.canGenerateThumbnail(for: item)
                        }
                        guard canGenerate else { return nil }

                        let hasCached = await MainActor.run {
                            FSItemIconUtils.getThumbnail(for: item.fullPath) != nil
                        }
                        if hasCached {
                            return item.fullPath
                        }

                        let url = URL(fileURLWithPath: item.fullPath)
                        if let thumbnail = await ThumbnailGeneratorUtils.generateThumbnail(
                            for: url,
                            size: size,
                            scale: scale,
                        ) {
                            await MainActor.run {
                                FSItemIconUtils.saveThumbnail(thumbnail, for: item.fullPath)
                            }
                            return item.fullPath
                        }
                        return nil
                    }
                }

                var readyPaths: [String] = []
                for await path in group {
                    if let path {
                        readyPaths.append(path)

                        // 10개마다 일괄 업데이트
                        if readyPaths.count >= 10 {
                            await send(.thumbnailsReady(paths: readyPaths))
                            readyPaths = []
                        }
                    }
                }

                // 남은 항목 처리
                if !readyPaths.isEmpty {
                    await send(.thumbnailsReady(paths: readyPaths))
                }
            }
        }
    }

    private func getSelectedItems(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<FSItem>,
    ) -> [FSItem] {
        Array(items.filter { selectedIds.contains($0.id) })
    }

    private func getSelectedFiles(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<FSItem>,
    ) -> [FSItem] {
        getSelectedItems(selectedIds: selectedIds, items: items).filter { !$0.isDirectory }
    }

    private func isPackageItem(_ item: FSItem) -> Bool {
        guard item.isDirectory else { return false }

        let url = URL(fileURLWithPath: item.fullPath)
        if let values = try? url.resourceValues(forKeys: [.isPackageKey]),
           values.isPackage == true
        {
            return true
        }

        let ext = item.fileExtension.lowercased()
        if ["app", "icon"].contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: item.fileExtension),
           type.conforms(to: .package)
        {
            return true
        }

        return false
    }

    private func preloadApplicationsEffect(
        selectedIds: Set<String>,
        items: IdentifiedArrayOf<FSItem>,
        currentItemId: String? = nil,
    ) -> Effect<Action> {
        let selectedFiles = getSelectedFiles(selectedIds: selectedIds, items: items)

        if selectedFiles.count > 1 {
            return .send(.operations(.loadCommonApplicationsForFiles(files: selectedFiles)))
        } else if selectedFiles.count == 1, let file = selectedFiles.first {
            return .send(.operations(.loadApplicationsForFile(file: file)))
        } else if let itemId = currentItemId,
                  let item = items.first(where: { $0.id == itemId }),
                  !item.isDirectory
        {
            return .send(.operations(.loadApplicationsForFile(file: item)))
        }
        return .none
    }
}

// swiftlint:enable type_body_length

enum ModifierFlags: Equatable, Sendable {
    case none
    case command
    case shift
}

struct ListRowDragSelection: Equatable, Sendable {
    var startItemId: String
    var currentItemId: String
    var initialSelectedIds: Set<String>
    var modifierFlags: ModifierFlags
}

struct LassoSelection: Equatable, Sendable {
    var startPoint: CGPoint
    var currentPoint: CGPoint
    var initialSelectedIds: Set<String>
    var modifierFlags: ModifierFlags

    var rect: CGRect {
        let minX = min(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let maxX = max(startPoint.x, currentPoint.x)
        let maxY = max(startPoint.y, currentPoint.y)

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY,
        )
    }
}

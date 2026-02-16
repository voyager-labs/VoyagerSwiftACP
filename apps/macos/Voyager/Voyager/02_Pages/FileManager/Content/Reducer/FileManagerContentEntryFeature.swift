import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@Reducer
struct FileManagerContentEntryFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient
    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .entries(entriesAction) = action else {
                return .none
            }

            return handleEntryAction(entriesAction, state: &state)
        }
    }

    private func handleEntryAction(
        _ action: EntryFeature.Action,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .handleDropToTag(providers, tagName):
            return .run { @MainActor send in
                let paths = await Self.resolveDroppedPaths(from: providers)
                guard !paths.isEmpty else { return }
                await send(.entryOperations(.toggleTagForDroppedPaths(paths: paths, tagName: tagName)))
            }

        case let .setDropTargeted(isTargeted):
            state.entryViewLayout.isDropTargeted = isTargeted
            return .none

        case let .startDrag(paths):
            entryFileOpsClient.saveDragPaths(paths)
            return .none

        case let .handleDrop(_, destinationPath):
            let internalPaths = entryFileOpsClient.loadDragPaths()
            guard !internalPaths.isEmpty else { return .none }
            let operation: ClipboardOperation = entryFileOpsClient.loadDragWithOption() ? .copy : .cut
            return .send(.entryOperations(.pasteItems(
                sourcePaths: internalPaths,
                destinationPath: destinationPath,
                operation: operation,
                actionKind: .paste,
            )))

        case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
            return .send(.entryOperations(.pasteItems(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                operation: isOptionDrag ? .copy : .cut,
                actionKind: .paste,
            )))

        case let .loadItems(path):
            return .send(.entryOperations(.loadItems(
                path: path,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))

        case let .loadRecentItems(showHidden):
            return .send(.entryOperations(.loadRecentItems(showHidden: showHidden)))

        case let .loadTagItems(tagName, showHidden):
            return .send(.entryOperations(.loadTagItems(tagName: tagName, showHidden: showHidden)))

        case .loadComputerItems:
            return .send(.entryOperations(.loadComputerItems))

        case let .itemsLoaded(items):
            state.navigation.titlePath = state.navigation.currentPath
            return .merge(
                .send(.entryOperations(.itemsLoaded(items))),
                .send(.entryArrangements(.reapply)),
            )

        case let .collectionItemsLoadedFromSearch(items):
            return .merge(
                .send(.entryOperations(.collectionItemsLoadedFromSearch(
                    items: items,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
                .send(.entryArrangements(.reapply)),
            )

        case let .setCollectionMode(isCollectionMode):
            state.composer.isCollectionMode = isCollectionMode
            return .merge(
                .send(.entryOperations(.setCollectionMode(isCollectionMode))),
                .send(.entryArrangements(.reapply)),
            )

        case .clearCollectionItems:
            return .send(.entryOperations(.clearCollectionItems))

        case .reloadCurrentFolder:
            return reloadEntryItemsEffect(state: state)

        case .reloadItems:
            return .send(.entryOperations(.loadItems(
                path: state.navigation.currentPath,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))

        case .toggleShowHiddenFiles:
            state.entryViewLayout.showHiddenFiles.toggle()
            return reloadEntryItemsEffect(state: state)

        case let .applyShowHiddenFiles(show):
            guard state.entryViewLayout.showHiddenFiles != show else { return .none }
            state.entryViewLayout.showHiddenFiles = show
            return reloadEntryItemsEffect(state: state)

        case let .setShowHidden(show):
            state.entryViewLayout.showHiddenFiles = show
            return .none

        case .selectAll:
            let displayItems = state.entryOperations.displayOrderItems
            state.entryViewLayout.selectedIds = Set(displayItems.map(\.id))
            state.entryViewLayout.lastSelectedId = displayItems.last?.id
            state.entryViewLayout.rangeAnchorId = state.entryViewLayout.lastSelectedId
            return .none

        case .clearSelection:
            state.entryViewLayout.selectedIds = []
            state.entryViewLayout.lastSelectedId = nil
            state.entryViewLayout.rangeAnchorId = nil
            state.entryViewLayout.shouldScrollToSelection = false
            return .none

        case let .selectNextItem(isShiftPressed):
            return applySelectionOffset(
                offset: 1,
                isShiftPressed: isShiftPressed,
                state: &state,
            )

        case let .selectPreviousItem(isShiftPressed):
            return applySelectionOffset(
                offset: -1,
                isShiftPressed: isShiftPressed,
                state: &state,
            )

        case let .selectByOffset(offset, isShiftPressed):
            return applySelectionOffset(
                offset: offset,
                isShiftPressed: isShiftPressed,
                state: &state,
            )

        case let .startRename(id):
            state.entryViewLayout.renamingItemId = id
            state.entryViewLayout.renamingText = state.entryOperations.displayItems[id: id]?.name ?? ""
            return .none

        case let .updateRenamingText(text):
            state.entryViewLayout.renamingText = text
            return .none

        case .cancelRename:
            state.entryViewLayout.renamingItemId = nil
            state.entryViewLayout.renamingText = ""
            return .none

        case .commitRename:
            guard let itemId = state.entryViewLayout.renamingItemId,
                  let item = state.entryOperations.displayItems[id: itemId]
            else {
                state.entryViewLayout.renamingItemId = nil
                state.entryViewLayout.renamingText = ""
                return .none
            }

            let trimmed = state.entryViewLayout.renamingText.trimmingCharacters(in: .whitespaces)
            state.entryViewLayout.renamingItemId = nil
            state.entryViewLayout.renamingText = ""

            guard !trimmed.isEmpty, trimmed != item.name else {
                return .none
            }

            let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent()
            let newPath = parentPath.appendingPathComponent(trimmed).path
            return .send(.entryOperations(.renameItem(oldPath: item.fullPath, newPath: newPath)))

        case let .createNewFolder(currentPath):
            var folderName = "untitled folder"
            var counter = 2
            while state.entryOperations.displayItems.contains(where: { $0.name == folderName }) {
                folderName = "untitled folder \(counter)"
                counter += 1
            }
            return .send(.entryOperations(.createNewFolder(name: folderName, parentPath: currentPath)))

        case .openSelectedItem:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }

            if selectedEntries.count == 1,
               let entry = selectedEntries.first,
               entry.isDirectory
            {
                return .send(.entries(.navigateFolder(id: entry.id)))
            }

            return .send(.entryOperations(.openFiles(files: selectedEntries)))

        case .quickLookSelectedItem:
            let selectedEntries = selectedEntries(from: state)
            if selectedEntries.count == 1, let file = selectedEntries.first {
                return .send(.entryOperations(.quickLookFile(file: file)))
            }
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.quickLookFiles(files: selectedEntries)))

        case .copySelectedItems:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.copySelectedItems(files: selectedEntries)))

        case .cutSelectedItems:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .merge(
                .send(.entryOperations(.copySelectedItems(files: selectedEntries))),
                .send(.entryOperations(.setClipboardOperation(operation: .cut))),
            )

        case let .pasteItems(destinationPath):
            return .send(.entryOperations(.pasteItemsFromClipboard(destinationPath: destinationPath)))

        case .duplicateSelectedItems:
            let selectedPaths = selectedEntries(from: state).map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.pasteItems(
                sourcePaths: selectedPaths,
                destinationPath: state.navigation.currentPath,
                operation: .copy,
                actionKind: .duplicate,
            )))

        case .createAliasForSelectedItems:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.createAliases(items: selectedEntries)))

        case .copySelectedAbsolutePaths:
            let selectedPaths = selectedEntries(from: state).map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.copyAbsolutePaths(paths: selectedPaths)))

        case .copySelectedURLs:
            let selectedPaths = selectedEntries(from: state).map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.copyURLs(paths: selectedPaths)))

        case .moveSelectedItemsToTrash:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.moveToTrash(items: selectedEntries)))

        case .deleteSelectedItemsImmediately:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.deleteImmediately(items: selectedEntries)))

        case .putBackSelectedItems:
            let selectedEntries = selectedEntries(from: state)
            guard !selectedEntries.isEmpty else { return .none }
            return .send(.entryOperations(.putBackFromTrash(items: selectedEntries)))

        case .emptyTrash:
            return .send(.entryOperations(.emptyTrash(items: state.entryOperations.displayOrderItems)))

        case let .delegate(.intent(intent)):
            return .send(.entryOperations(mapOperationsAction(from: intent)))

        case let .delegate(.openFoldersInNewWindows(paths)):
            return .run { [fileManagerWindowClient] _ in
                for path in paths {
                    await fileManagerWindowClient.openPathInNewWindow(path)
                }
            }

        case let .delegate(.focusWindow(path)):
            return .run { [fileManagerWindowClient] _ in
                await fileManagerWindowClient.focusPath(path)
            }

        default:
            return .none
        }
    }

    private func selectedEntries(from state: State) -> [EntryState] {
        let selectedIds = state.entryViewLayout.selectedIds
        guard !selectedIds.isEmpty else { return [] }
        return state.entryOperations.displayItems.filter { selectedIds.contains($0.id) }
    }

    private func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        switch state.navigation.navigationState {
        case let .folder(path):
            .send(.entryOperations(.loadItems(
                path: path,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .recents:
            .send(.entryOperations(.loadRecentItems(showHidden: state.entryViewLayout.showHiddenFiles)))
        case let .tags(tagName):
            .send(.entryOperations(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .computer:
            .send(.entryOperations(.loadComputerItems))
        case .collection:
            .none
        }
    }

    private func applySelectionOffset(
        offset: Int,
        isShiftPressed: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let displayItems = state.entryOperations.displayOrderItems
        guard !displayItems.isEmpty else { return .none }

        guard let currentId = state.entryViewLayout.lastSelectedId,
              let currentIndex = displayItems.firstIndex(where: { $0.id == currentId })
        else {
            let fallbackItem = offset >= 0 ? displayItems.first : displayItems.last
            guard let item = fallbackItem else { return .none }
            state.entryViewLayout.selectedIds = [item.id]
            state.entryViewLayout.lastSelectedId = item.id
            state.entryViewLayout.rangeAnchorId = item.id
            state.entryViewLayout.shouldScrollToSelection = true
            return .none
        }

        let targetIndex: Int
        if abs(offset) > 1 {
            let columnCount = max(1, state.entryViewLayout.gridColumnCount)
            let currentRow = currentIndex / columnCount
            let currentCol = currentIndex % columnCount
            let targetRow = currentRow + (offset > 0 ? 1 : -1)
            let totalRows = (displayItems.count + columnCount - 1) / columnCount

            guard targetRow >= 0, targetRow < totalRows else { return .none }

            let targetRowStart = targetRow * columnCount
            let targetRowEnd = min(displayItems.count - 1, (targetRow + 1) * columnCount - 1)
            var candidate = targetRowStart + currentCol
            if candidate > targetRowEnd {
                candidate = targetRowEnd
            }
            targetIndex = candidate
        } else {
            targetIndex = max(0, min(displayItems.count - 1, currentIndex + offset))
        }

        let targetItem = displayItems[targetIndex]
        if isShiftPressed {
            let anchorId = state.entryViewLayout.rangeAnchorId ?? currentId
            guard let anchorIndex = displayItems.firstIndex(where: { $0.id == anchorId }) else { return .none }
            let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
            state.entryViewLayout.selectedIds = Set(displayItems[range].map(\.id))
            state.entryViewLayout.rangeAnchorId = anchorId
        } else {
            state.entryViewLayout.selectedIds = [targetItem.id]
            state.entryViewLayout.rangeAnchorId = targetItem.id
        }
        state.entryViewLayout.lastSelectedId = targetItem.id
        state.entryViewLayout.shouldScrollToSelection = true
        return .none
    }

    private static func resolveDroppedPaths(from providers: [NSItemProvider]) async -> [String] {
        var paths: [String] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let path = await resolveDroppedPath(from: provider) {
                paths.append(path)
            }
        }
        return paths
    }

    private static func resolveDroppedPath(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url.path)
                    return
                }

                if let data = item as? Data {
                    if let urlString = String(data: data, encoding: .utf8),
                       let url = URL(string: urlString)
                    {
                        continuation.resume(returning: url.path)
                        return
                    }

                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url.path)
                        return
                    }

                    continuation.resume(returning: nil)
                    return
                }

                if let urlString = item as? String,
                   let url = URL(string: urlString)
                {
                    continuation.resume(returning: url.path)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func mapOperationsAction(from intent: EntryIntent) -> EntryOperationsAction {
        if let action = mapOpenAction(from: intent) {
            return action
        }

        if let action = mapOpenWithAction(from: intent) {
            return action
        }

        if let action = mapEditAction(from: intent) {
            return action
        }

        if let action = mapClipboardAction(from: intent) {
            return action
        }

        if let action = mapTrashAction(from: intent) {
            return action
        }

        switch intent {
        case let .compressItems(items):
            return .compressItems(items: items)
        case let .extractCompressedFile(file):
            return .extractCompressedFile(file: file)
        case let .setTagsForItems(targets):
            return .setTagsForItems(targets: targets)
        case let .toggleTagForDroppedPaths(paths, tagName):
            return .toggleTagForDroppedPaths(paths: paths, tagName: tagName)
        case let .loadCommonApplicationsForFiles(files):
            return .loadCommonApplicationsForFiles(files: files)
        case let .replayEntryAction(direction, record):
            return .replayEntryAction(direction: direction, record: record)
        default:
            preconditionFailure("Unhandled EntryIntent routing")
        }
    }

    private func mapOpenAction(from intent: EntryIntent) -> EntryOperationsAction? {
        switch intent {
        case let .openFiles(files):
            .openFiles(files: files)
        case let .quickLookFile(file):
            .quickLookFile(file: file)
        case let .quickLookFiles(files):
            .quickLookFiles(files: files)
        case let .openFinderInfo(items):
            .openFinderInfo(items: items)
        case let .shareItems(items, anchor):
            .shareItems(items: items, anchor: anchor)
        case let .performService(items, name):
            .performService(items: items, name: name)
        case let .revealInFinder(items):
            .revealInFinder(items: items)
        default:
            nil
        }
    }

    private func mapOpenWithAction(from intent: EntryIntent) -> EntryOperationsAction? {
        switch intent {
        case let .openFileWithApp(file):
            .openFileWithApp(file: file)
        case let .openFileWithAppBundleID(filePath, bundleID, url):
            .openFileWithAppBundleID(filePath: filePath, bundleID: bundleID, url: url)
        case let .setDefaultAppForFile(type, bundleID, file):
            .setDefaultAppForFile(type: type, bundleID: bundleID, file: file)
        case let .setDefaultAppWithOther(file):
            .setDefaultAppWithOther(file: file)
        case let .openFilesWithAppFromOther(files, shouldSetAsDefault):
            .openFilesWithAppFromOther(files: files, shouldSetAsDefault: shouldSetAsDefault)
        case let .loadApplicationsForFile(file):
            .loadApplicationsForFile(file: file)
        default:
            nil
        }
    }

    private func mapEditAction(from intent: EntryIntent) -> EntryOperationsAction? {
        switch intent {
        case let .createNewFolder(name, parentPath):
            .createNewFolder(name: name, parentPath: parentPath)
        case let .createAliases(items):
            .createAliases(items: items)
        case let .renameItem(oldPath, newPath):
            .renameItem(oldPath: oldPath, newPath: newPath)
        default:
            nil
        }
    }

    private func mapClipboardAction(from intent: EntryIntent) -> EntryOperationsAction? {
        switch intent {
        case let .copySelectedItems(files):
            .copySelectedItems(files: files)
        case .loadClipboardState:
            .loadClipboardState
        case let .copyAbsolutePaths(paths):
            .copyAbsolutePaths(paths: paths)
        case let .copyURLs(paths):
            .copyURLs(paths: paths)
        case let .setClipboardOperation(operation):
            .setClipboardOperation(operation: operation)
        case let .pasteItemsFromClipboard(destinationPath):
            .pasteItemsFromClipboard(destinationPath: destinationPath)
        case let .pasteItems(sourcePaths, destinationPath, operation, actionKind):
            .pasteItems(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                operation: operation,
                actionKind: actionKind,
            )
        default:
            nil
        }
    }

    private func mapTrashAction(from intent: EntryIntent) -> EntryOperationsAction? {
        switch intent {
        case let .moveToTrash(items):
            .moveToTrash(items: items)
        case let .deleteImmediately(items):
            .deleteImmediately(items: items)
        case let .putBackFromTrash(items):
            .putBackFromTrash(items: items)
        case let .emptyTrash(items):
            .emptyTrash(items: items)
        default:
            nil
        }
    }
}

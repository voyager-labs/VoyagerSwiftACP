import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentEntryFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

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
}

private extension FileManagerContentEntryFeature {
    private func handleEntryAction(
        _ action: EntryCommandAction,
        state: inout State,
    ) -> Effect<Action> {
        if let effect = handleDragAndDropActions(action) { return effect }
        if let effect = handleLoadingAndCollectionActions(action, state: &state) { return effect }
        if let effect = handleReloadAndVisibilityActions(action, state: &state) { return effect }
        if let effect = handleSelectionActions(action, state: state) { return effect }
        if let effect = handleRenameAndCreationActions(action, state: &state) { return effect }
        if let effect = handleOpenAndClipboardActions(action, state: state) { return effect }
        if let effect = handleTrashActions(action, state: state) { return effect }
        return .none
    }

    private func handleDragAndDropActions(
        _ action: EntryCommandAction,
    ) -> Effect<Action>? {
        switch action {
        case let .handleDropToTag(providers, tagName):
            return .run { @MainActor send in
                let paths = await resolveEntryDroppedPaths(from: providers)
                guard !paths.isEmpty else { return }
                send(.entryOperations(.requestTagMutation(request: .init(
                    mode: .add,
                    tagName: tagName,
                    paths: paths,
                ))))
            }
        case let .setDropTargeted(isTargeted):
            return .send(.entryViewLayout(.setDropTargeted(isTargeted)))
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
        default:
            return nil
        }
    }

    private func handleLoadingAndCollectionActions(
        _ action: EntryCommandAction,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case let .loadItems(path):
            return .send(.entryOperations(.loadItems(path: path, showHidden: state.entryViewLayout.showHiddenFiles)))
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
        default:
            return nil
        }
    }

    private func handleReloadAndVisibilityActions(
        _ action: EntryCommandAction,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .reloadCurrentFolder:
            return reloadEntryItemsEffect(state: state)
        case .reloadItems:
            return .send(.entryOperations(.loadItems(
                path: state.navigation.currentPath,
                showHidden: state.entryViewLayout.showHiddenFiles,
            )))
        case .toggleShowHiddenFiles:
            return reloadEntryItemsEffect(state: state)
        case let .applyShowHiddenFiles(show):
            guard state.entryViewLayout.showHiddenFiles != show else { return .none }
            var reloadedState = state
            reloadedState.entryViewLayout.showHiddenFiles = show
            return .concatenate(
                .send(.entryViewLayout(.setShowHiddenFiles(show))),
                reloadEntryItemsEffect(state: reloadedState),
            )
        case let .setShowHidden(show):
            return .send(.entryViewLayout(.setShowHiddenFiles(show)))
        default:
            return nil
        }
    }

    private func handleSelectionActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .selectAll:
            .send(.entryViewLayout(.applySelectAll(
                orderedItemIds: state.entryOperations.displayOrderItems.map(\.id),
            )))
        case .clearSelection:
            .send(.entryViewLayout(.applyClearSelection))
        case let .selectNextItem(isShiftPressed):
            .send(.entryViewLayout(.applySelectionOffset(
                offset: 1,
                isShiftPressed: isShiftPressed,
                orderedItemIds: state.entryOperations.displayOrderItems.map(\.id),
            )))
        case let .selectPreviousItem(isShiftPressed):
            .send(.entryViewLayout(.applySelectionOffset(
                offset: -1,
                isShiftPressed: isShiftPressed,
                orderedItemIds: state.entryOperations.displayOrderItems.map(\.id),
            )))
        case let .selectByOffset(offset, isShiftPressed):
            .send(.entryViewLayout(.applySelectionOffset(
                offset: offset,
                isShiftPressed: isShiftPressed,
                orderedItemIds: state.entryOperations.displayOrderItems.map(\.id),
            )))
        default:
            nil
        }
    }

    private func handleRenameAndCreationActions(
        _ action: EntryCommandAction,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case let .startRename(id):
            return .send(.entryViewLayout(.setRenameState(
                id: id,
                text: state.entryOperations.displayItems[id: id]?.name ?? "",
            )))
        case let .updateRenamingText(text):
            return .send(.entryViewLayout(.updateRenamingText(text)))
        case .cancelRename:
            return .send(.entryViewLayout(.cancelRename))
        case .commitRename:
            guard let itemId = state.entryViewLayout.renamingItemId,
                  let item = state.entryOperations.displayItems[id: itemId]
            else {
                return .send(.entryViewLayout(.cancelRename))
            }
            let trimmed = state.entryViewLayout.renamingText.trimmingCharacters(in: .whitespaces)
            let clearRenameStateEffect: Effect<Action> = .send(.entryViewLayout(.cancelRename))
            guard !trimmed.isEmpty, trimmed != item.name else { return clearRenameStateEffect }
            let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent()
            let newPath = parentPath.appendingPathComponent(trimmed).path
            return .concatenate(
                clearRenameStateEffect,
                .send(.entryOperations(.renameItem(oldPath: item.fullPath, newPath: newPath))),
            )
        case let .createNewFolder(currentPath):
            var folderName = "untitled folder"
            var counter = 2
            while state.entryOperations.displayItems.contains(where: { $0.name == folderName }) {
                folderName = "untitled folder \(counter)"
                counter += 1
            }
            return .send(.entryOperations(.createNewFolder(name: folderName, parentPath: currentPath)))
        default:
            return nil
        }
    }

    private func handleOpenAndClipboardActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        if let effect = handleOpenActions(action, state: state) { return effect }
        if let effect = handleClipboardActions(action, state: state) { return effect }
        if let effect = handleAliasAndTagActions(action, state: state) { return effect }
        return nil
    }

    private func handleOpenActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .openSelectedItem:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            if selected.count == 1, let entry = selected.first, entry.isDirectory {
                return .send(.entries(.navigateFolder(id: entry.id)))
            }
            return .send(.entryOperations(.openFiles(files: selected)))
        case .quickLookSelectedItem:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            if selected.count == 1, let file = selected.first {
                return .send(.entryOperations(.quickLookFile(file: file)))
            }
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.quickLookFiles(files: selected)))
        default:
            return nil
        }
    }

    private func handleClipboardActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        if let effect = handleCopyPasteActions(action, state: state) { return effect }
        if let effect = handleDuplicateAndPathCopyActions(action, state: state) { return effect }
        return nil
    }

    private func handleCopyPasteActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .copySelectedItems:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.copySelectedItems(files: selected)))
        case .cutSelectedItems:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .merge(
                .send(.entryOperations(.copySelectedItems(files: selected))),
                .send(.entryOperations(.setClipboardOperation(operation: .cut))),
            )
        case let .pasteItems(destinationPath):
            return .send(.entryOperations(.pasteItemsFromClipboard(destinationPath: destinationPath)))
        default:
            return nil
        }
    }

    private func handleDuplicateAndPathCopyActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .duplicateSelectedItems:
            let selectedIds = state.entryViewLayout.selectedIds
            let selectedPaths = state.entryOperations.displayItems
                .filter { selectedIds.contains($0.id) }
                .map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.pasteItems(
                sourcePaths: selectedPaths,
                destinationPath: state.navigation.currentPath,
                operation: .copy,
                actionKind: .duplicate,
            )))
        case .copySelectedAbsolutePaths:
            let selectedIds = state.entryViewLayout.selectedIds
            let selectedPaths = state.entryOperations.displayItems
                .filter { selectedIds.contains($0.id) }
                .map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.copyAbsolutePaths(paths: selectedPaths)))
        case .copySelectedURLs:
            let selectedIds = state.entryViewLayout.selectedIds
            let selectedPaths = state.entryOperations.displayItems
                .filter { selectedIds.contains($0.id) }
                .map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.copyURLs(paths: selectedPaths)))
        default:
            return nil
        }
    }

    private func handleAliasAndTagActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .createAliasForSelectedItems:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.createAliases(items: selected)))
        case let .toggleTagForSelectedItem(tag):
            let selectedIds = state.entryViewLayout.selectedIds
            let selectedPaths = state.entryOperations.displayItems
                .filter { selectedIds.contains($0.id) }
                .map(\.fullPath)
            guard !selectedPaths.isEmpty else { return .none }
            return .send(.entryOperations(.requestTagMutation(request: .init(
                mode: .toggle,
                tagName: tag,
                paths: selectedPaths,
            ))))
        default:
            return nil
        }
    }

    private func handleTrashActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        switch action {
        case .moveSelectedItemsToTrash:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.moveToTrash(items: selected)))
        case .deleteSelectedItemsImmediately:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.deleteImmediately(items: selected)))
        case .putBackSelectedItems:
            let selectedIds = state.entryViewLayout.selectedIds
            let selected = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
            guard !selected.isEmpty else { return .none }
            return .send(.entryOperations(.putBackFromTrash(items: selected)))
        case .emptyTrash:
            return .send(.entryOperations(.emptyTrash(items: state.entryOperations.displayOrderItems)))
        default:
            return nil
        }
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
}

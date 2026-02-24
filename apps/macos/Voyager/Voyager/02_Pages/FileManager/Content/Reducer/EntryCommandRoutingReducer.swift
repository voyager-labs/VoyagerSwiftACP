#if canImport(ComposableArchitecture)
import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct EntryCommandRoutingReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.entryFileOpsClient)
    private var entryFileOpsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if let effect = routeSidebarDropAction(action) { return effect }

            guard case let .entries(entriesAction) = action else {
                return .none
            }

            return handleEntryAction(entriesAction, state: &state)
        }
    }
}

private extension EntryCommandRoutingReducer {
    private func routeSidebarDropAction(_ action: Action) -> Effect<Action>? {
        switch action {
        case let .dropItemsToSidebarFolder(providers, targetURL):
            .send(.entries(.handleDrop(
                providers: providers,
                destinationPath: targetURL.path,
            )))
        case let .dropItemsToTag(providers, tagName):
            .send(.entries(.handleDropToTag(
                providers: providers,
                tagName: tagName,
            )))
        default:
            nil
        }
    }

    private func handleEntryAction(
        _ action: EntryCommandAction,
        state: inout State,
    ) -> Effect<Action> {
        if let effect = handleDragAndDropActions(action) { return effect }
        if let effect = handleLoadingAndCollectionActions(action, state: &state) { return effect }
        if let effect = handleReloadAndVisibilityActions(action, state: &state) { return effect }
        if let effect = handleSelectionActions(action, state: state) { return effect }
        if let effect = handleRenameAndCreationActions(action, state: &state) { return effect }
        if let effect = handleEntryOperationCommandActions(action, state: state) { return effect }
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

    private func handleEntryOperationCommandActions(
        _ action: EntryCommandAction,
        state: State,
    ) -> Effect<Action>? {
        guard let command = mapEntryOperationCommand(action) else { return nil }

        let outputs = EntryOperationsCommandPlanner.plan(
            command: command,
            context: .init(
                selectedIds: state.entryViewLayout.selectedIds,
                displayItems: state.entryOperations.displayOrderItems,
                currentPath: state.navigation.currentPath,
            ),
        )

        guard !outputs.isEmpty else { return .none }
        return .merge(outputs.map(effect(for:)))
    }

    private func mapEntryOperationCommand(_ action: EntryCommandAction) -> EntryOperationsCommand? {
        if let command = mapNavigationCommand(action) {
            return .navigation(command)
        }
        if let command = mapClipboardCommand(action) {
            return .clipboard(command)
        }
        if let command = mapMutationCommand(action) {
            return .mutation(command)
        }
        return nil
    }

    private func mapNavigationCommand(_ action: EntryCommandAction) -> EntryOperationsNavigationCommand? {
        switch action {
        case .openSelectedItem:
            .openSelectedItem
        case .quickLookSelectedItem:
            .quickLookSelectedItem
        case .getInfoForSelectedItems:
            .getInfoForSelectedItems
        case let .shareSelectedItems(anchor):
            .shareSelectedItems(anchor: anchor)
        case .revealSelectedItemsInFinder:
            .revealSelectedItemsInFinder
        case let .performService(serviceName):
            .performService(serviceName: serviceName)
        case let .openWithSelectedItem(bundleID, shouldSetAsDefault):
            .openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: shouldSetAsDefault)
        default:
            nil
        }
    }

    private func mapClipboardCommand(_ action: EntryCommandAction) -> EntryOperationsClipboardCommand? {
        switch action {
        case .copySelectedItems:
            .copySelectedItems
        case .cutSelectedItems:
            .cutSelectedItems
        case let .pasteItems(destinationPath):
            .pasteItems(destinationPath: destinationPath)
        case .duplicateSelectedItems:
            .duplicateSelectedItems
        case .copySelectedAbsolutePaths:
            .copySelectedAbsolutePaths
        case .copySelectedURLs:
            .copySelectedURLs
        default:
            nil
        }
    }

    private func mapMutationCommand(_ action: EntryCommandAction) -> EntryOperationsMutationCommand? {
        switch action {
        case .createAliasForSelectedItems:
            .createAliasForSelectedItems
        case .compressSelectedItems:
            .compressSelectedItems
        case .extractSelectedItem:
            .extractSelectedItem
        case let .toggleTagForSelectedItem(tag):
            .toggleTagForSelectedItem(tag: tag)
        case .moveSelectedItemsToTrash:
            .moveSelectedItemsToTrash
        case .deleteSelectedItemsImmediately:
            .deleteSelectedItemsImmediately
        case .putBackSelectedItems:
            .putBackSelectedItems
        case .emptyTrash:
            .emptyTrash
        default:
            nil
        }
    }

    private func effect(for output: EntryOperationsCommandOutput) -> Effect<Action> {
        switch output {
        case let .entryOperations(action):
            .send(.entryOperations(action))
        case let .navigateFolder(id):
            .send(.entries(.navigateFolder(id: id)))
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

#else

struct EntryCommandRoutingReducer {}

#endif

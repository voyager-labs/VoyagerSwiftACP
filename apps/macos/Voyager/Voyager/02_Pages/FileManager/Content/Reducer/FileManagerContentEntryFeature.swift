import ComposableArchitecture

@Reducer
struct FileManagerContentEntryFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient

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
        case let .delegate(.intent(intent)):
            return .send(.entryOperations(mapOperationsAction(from: intent)))

        case .itemsLoaded:
            state.navigation.titlePath = state.navigation.currentPath
            return .send(.entryArrangements(.reapply))

        case .collectionItemsLoadedFromSearch:
            return .send(.entryArrangements(.reapply))

        case .setCollectionMode, .operationFinished:
            return .send(.entryArrangements(.reapply))

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

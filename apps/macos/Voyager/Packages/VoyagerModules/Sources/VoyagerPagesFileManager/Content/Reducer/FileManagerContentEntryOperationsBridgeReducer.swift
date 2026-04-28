import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentEntryOperationsBridgeReducer {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            if let effect = handleEntryViewLayoutDelegateBridgeAction(action, state: &state) {
                return effect
            }

            if let effect = handleEntryOperationsDelegateAction(action) {
                return effect
            }

            if let effect = handleEntryOperationsBridgeAction(action, state: &state) {
                return effect
            }

            switch action {
            case let .delegate(.dropItemsToSidebarFolder(providers, targetURL)):
                return sendEntryOperations(.routing(.handleDrop(
                    providers: providers,
                    destinationPath: targetURL.path,
                )))

            case let .delegate(.dropItemsToTag(providers, tagName)):
                return sendEntryOperations(.routing(.handleDropToTag(
                    providers: providers,
                    tagName: tagName,
                )))

            case .internal(.systemAppDidBecomeActive):
                let entryOperationsAction = EntryOperationsAction.lifecycle(.appDidBecomeActive)
                return sendEntryOperations(entryOperationsAction)

            default:
                return .none
            }
        }
    }

    private func handleEntryViewLayoutDelegateBridgeAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entryViewLayout(.delegate(delegateAction)) = action else {
            return nil
        }

        switch delegateAction {
        case let .executeCommand(command):
            let entryOperationsAction = EntryOperationsAction.routing(.executeCommand(
                command: command,
                context: makeEntryOperationsCommandContext(state: state),
            ))
            return sendEntryOperations(entryOperationsAction)

        case let .saveScrollOffset(offset, path):
            return .send(.internal(.saveScrollOffset(offset, forPath: path)))

        case let .openPathInNewTab(path):
            return .send(.delegate(.openPathInNewTab(path)))

        case let .startRename(item, text):
            let entryOperationsAction = EntryOperationsAction.edit(.startRename(item: item, text: text))
            return sendEntryOperations(entryOperationsAction)
        }
    }

    func handleEntryOperationsDelegateAction(_ action: Action) -> Effect<Action>? {
        guard case let .entryViewLayout(.entryOperations(.delegate(delegate))) = action else {
            return nil
        }

        switch delegate {
        case let .navigateToPath(path):
            let navigationAction: ContentPageNavigationAction = .view(.navigateToPath(path))
            let forwardedAction = FileManagerContentAction.internal(.requestNavigation(navigationAction))
            return .send(forwardedAction)

        case let .openCollectionFile(url):
            let navigationAction: ContentPageNavigationAction = .view(.openCollectionFile(url))
            let forwardedAction = FileManagerContentAction.internal(.requestNavigation(navigationAction))
            return .send(forwardedAction)
        }
    }

    private func handleEntryOperationsBridgeAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entryViewLayout(.entryOperations(entryOperationsAction)) = action else {
            return nil
        }

        logEntryActionMetricIfNeeded(for: entryOperationsAction)
        return handleEntryOperationsAction(entryOperationsAction, state: &state)
    }

    public func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .loading(.itemsLoaded):
            .none

        case .lifecycle(.entryActionCompleted):
            .none

        case .lifecycle(.operationFinished):
            reloadEntryItemsEffect(state: state)

        case .lifecycle(.emptyTrashCompleted):
            .send(.delegate(.closeWindow))

        default:
            .none
        }
    }

    private func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
        )
    }

    private func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(path: path, showHidden: showHidden)))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(showHidden: showHidden)))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(tagName: tagName, showHidden: showHidden)))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection:
            .none
        }
    }

    func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        let forwardedAction = FileManagerContentAction.entryViewLayout(.entryOperations(action))
        return .send(forwardedAction)
    }

    public func makeEntryOperationsCommandContext(state: State) -> EntryOperationsCommandContext {
        EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: state.entryViewLayout.entries,
            currentPath: state.navigation.currentPath,
        )
    }
}

extension FileManagerContentEntryOperationsBridgeReducer {
    private struct EntryActionPayload {
        let actionKind: DAUEntryActionKind
        let entryKind: DAUEntryKind
    }

    private func logEntryActionMetricIfNeeded(for action: EntryOperationsAction) {
        guard let payload = dauEntryActionPayload(for: action) else {
            return
        }

        VoyagerSentryMetricLogger.logDAUEntryAction(
            actionKind: payload.actionKind,
            entryKind: payload.entryKind,
        )
    }

    private func dauEntryActionPayload(for action: EntryOperationsAction) -> EntryActionPayload? {
        payloadForOpenActions(action)
            ?? payloadForOpenWithActions(action)
            ?? payloadForCreateActions(action)
            ?? payloadForTrashActions(action)
            ?? payloadForArchiveActions(action)
            ?? payloadForTagActions(action)
    }

    private func payloadForOpenActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        guard case let .open(openAction) = action else {
            return nil
        }
        return payloadForOpenAction(openAction)
    }

    private func payloadForOpenWithActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .openWith(.openFileWithApp(file)):
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind(for: file))

        case let .openWith(.openFileWithAppBundleID(filePath, bundleID: _, url: _)):
            guard let entryKind = entryKind(for: [filePath]) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        case let .openWith(.setDefaultAppForFile(type: _, bundleID: _, file: file)):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .openWith(.setDefaultAppWithOther(file)):
            return EntryActionPayload(actionKind: .setDefaultApp, entryKind: entryKind(for: file))

        case let .openWith(.openFilesWithAppFromOther(files, shouldSetAsDefault: _)):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .openWithApp, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        payloadForEditCreateActions(action) ?? payloadForClipboardCreateActions(action)
    }

    private func payloadForTrashActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .trash(.moveToTrash(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .moveToTrash, entryKind: entryKind)

        case let .trash(.deleteImmediatelyConfirmed(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .deleteImmediately, entryKind: entryKind)

        case let .trash(.putBackFromTrash(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .putBack, entryKind: entryKind)

        case let .trash(.emptyTrashConfirmed(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .emptyTrash, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func payloadForArchiveActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .archive(.compressItems(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .compress, entryKind: entryKind)

        case let .archive(.extractCompressedFile(path)):
            return EntryActionPayload(actionKind: .extract, entryKind: entryKind(forPath: path))

        default:
            return nil
        }
    }

    private func payloadForTagActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .tagging(.requestTagMutation(request: request)):
            guard let entryKind = entryKind(for: request.paths) else { return nil }
            return EntryActionPayload(actionKind: .setTags, entryKind: entryKind)

        default:
            return nil
        }
    }

    private func entryKind(for entries: [EntryModel]) -> DAUEntryKind? {
        guard !entries.isEmpty else { return nil }
        let kinds = Set(entries.map(entryKind(for:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private func entryKind(for entry: EntryModel) -> DAUEntryKind {
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return .collection
        }
        return entry.isFolder ? .directory : .file
    }

    private func entryKind(for paths: [String]) -> DAUEntryKind? {
        guard !paths.isEmpty else { return nil }
        let kinds = Set(paths.map(entryKind(forPath:)))
        if kinds.count == 1, let kind = kinds.first {
            return kind
        }
        return .mixed
    }

    private func entryKind(forPath path: String) -> DAUEntryKind {
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if pathExtension == CollectionConstants.fileExtension {
            return .collection
        }
        return .file
    }

    private func dauActionKind(for operationKind: OperationKind) -> DAUEntryActionKind? {
        guard operationKind.isUndoable else { return nil }
        return Self.dauActionKindMap[operationKind]
    }

    private func payloadForOpenAction(_ action: EntryOperationsAction.Open) -> EntryActionPayload? {
        guard let (actionKind, paths) = openMetricInputs(for: action) else {
            return nil
        }
        return payload(actionKind: actionKind, paths: paths)
    }

    private func payloadForEditCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case .edit(.createNewFolder):
            return EntryActionPayload(actionKind: .createFolder, entryKind: .directory)
        case let .edit(.createAliases(paths)):
            guard let entryKind = entryKind(for: paths) else { return nil }
            return EntryActionPayload(actionKind: .createAlias, entryKind: entryKind)
        case let .edit(.renameItem(oldPath: oldPath, newPath: _)):
            guard let entryKind = entryKind(for: [oldPath]) else { return nil }
            return EntryActionPayload(actionKind: .rename, entryKind: entryKind)
        default:
            return nil
        }
    }

    private func payloadForClipboardCreateActions(_ action: EntryOperationsAction) -> EntryActionPayload? {
        switch action {
        case let .clipboard(.copySelectedItems(files)):
            guard let entryKind = entryKind(for: files) else { return nil }
            return EntryActionPayload(actionKind: .copy, entryKind: entryKind)
        case let .clipboard(.pasteItems(
            sourcePaths: sourcePaths,
            destinationPath: _,
            operation: _,
            operationKind: operationKind,
        )):
            guard let entryKind = entryKind(for: sourcePaths) else { return nil }
            guard let actionKind = dauActionKind(for: operationKind) else { return nil }
            return EntryActionPayload(actionKind: actionKind, entryKind: entryKind)
        default:
            return nil
        }
    }

    private func openMetricInputs(for action: EntryOperationsAction.Open) -> (DAUEntryActionKind, [String])? {
        switch action {
        case let .openFiles(paths):
            (.openDefault, paths)
        case let .quickLookFiles(paths):
            (.quickLook, paths)
        case let .openFinderInfo(paths):
            (.getInfo, paths)
        case let .shareItems(paths, _):
            (.share, paths)
        case let .performService(paths, _):
            (.performService, paths)
        case let .revealInFinder(paths):
            (.revealInFinder, paths)
        }
    }

    private func payload(
        actionKind: DAUEntryActionKind,
        paths: [String],
    ) -> EntryActionPayload? {
        guard let entryKind = entryKind(for: paths) else { return nil }
        return EntryActionPayload(actionKind: actionKind, entryKind: entryKind)
    }

    private static let dauActionKindMap: [OperationKind: DAUEntryActionKind] = [
        .rename: .rename,
        .pasteFileMove: .move,
        .pasteFileDuplicate: .duplicate,
        .pasteFileCopy: .paste,
        .createFolder: .createFolder,
        .createAlias: .createAlias,
        .moveToTrash: .moveToTrash,
        .putBack: .putBack,
        .setTags: .setTags,
    ]
}

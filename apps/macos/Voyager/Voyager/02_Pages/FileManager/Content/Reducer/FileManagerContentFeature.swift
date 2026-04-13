import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    private let systemNotificationsCancellationID = "FileManagerContent.systemNotifications"

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Reduce { state, action in
            if let effect = handleEntryViewLayoutDelegateBridgeAction(action, state: &state) {
                return effect
            }

            if let effect = handleEntryOperationsBridgeAction(action, state: &state) {
                return effect
            }

            if let effect = handleComposerAction(action, state: &state) {
                return effect
            }

            if let effect = handleCollectionDraftAction(action, state: &state) {
                return effect
            }

            switch action {
            case let .internal(.applyNavigationState(navigationState)):
                state.entryViewLayout.currentPath = state.navigation.currentPath
                state.entryViewLayout.savedScrollOffset = state.navigation.scrollPositions[state.navigation.currentPath]
                return applyNavigationStateEffect(navigationState, state: state)

            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

            case .view(.toggleShowHiddenFilesAndReload):
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: showHidden,
                    ),
                )

            case let .view(.handleKeyCommand(command)):
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case .delegate(.openPathInNewWindow),
                 .delegate(.openPathInNewTab),
                 .delegate(.closeWindow):
                return .none

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

            case let .view(.changeLayout(layout)):
                let currentMode = state.entryViewLayout.mode
                let isModeChanging = currentMode != layout
                let hasActiveRename = state.entryViewLayout.entryOperations.renamingItemId != nil

                state.entryViewLayout.mode = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)

                if isModeChanging, hasActiveRename {
                    return .send(.entryViewLayout(.entryOperations(.edit(.cancelRename))))
                }
                return .none

            case let .internal(.saveScrollOffset(offset, forPath: path)):
                state.navigation.scrollPositions[path] = offset
                if path == state.navigation.currentPath {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            case .internal(.startObservingSystemNotifications):
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSApplication.didBecomeActiveNotification,
                        nil,
                    ) {
                        await send(.internal(.systemAppDidBecomeActive))
                    }
                }
                .cancellable(id: systemNotificationsCancellationID, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .cancel(id: systemNotificationsCancellationID)

            case .internal(.systemAppDidBecomeActive):
                let entryOperationsAction = EntryOperationsAction.lifecycle(.appDidBecomeActive)
                return sendEntryOperations(entryOperationsAction)

            case .internal(.syncComposerCollectionState):
                state.syncComposerCollectionState()
                return .none

            default:
                return .none
            }
        }
    }

    private func handleEntryOperationsBridgeAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        if let effect = handleEntryOperationsDelegateAction(action) {
            return effect
        }

        guard case let .entryViewLayout(.entryOperations(entryOperationsAction)) = action else {
            return nil
        }

        logEntryActionMetricIfNeeded(for: entryOperationsAction)
        return handleEntryOperationsAction(entryOperationsAction, state: &state)
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

    func handleEntryOperationsAction(
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

    private func handleComposerAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .composer(composerAction) = action else {
            return nil
        }

        return FileManagerContentComposerCoordinator.reduce(
            composerAction,
            state: &state,
            dependencies: .init(
                collectionAlertClient: collectionAlertClient,
                computerName: fileManagerClient.displayName("/"),
            ),
        )
    }

    private func handleCollectionDraftAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .delegate(.discardCollectionChanges):
            guard let baseline = state.collectionSession.baseline,
                  state.isCollectionMode,
                  state.isOpenedCollectionDirty
            else {
                return .none
            }

            let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
            state.composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
            state.collectionContext = baseline.context
            state.syncComposerCollectionState()

            if state.collectionSession.openedURL == nil {
                state.composer.text = baseline.context.query
            } else {
                state.composer.text = ""
            }
            state.composer.scopes = baseline.context.scopes
            state.composer.conditions = baseline.context.conditions
            state.composer.propertyPicker = ConditionPropertyPickerFeature.State()
            state.composer.operatorPicker = OperatorPickerFeature.State()
            state.composer.valuePicker = ValuePickerFeature.State()
            state.composer.clearHistory()
            return .none
        default:
            return nil
        }
    }
}

extension FileManagerContentFeature {
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

    func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .recents:
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadRecentItems(
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case let .tags(tagName):
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .computer:
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadComputerItems)),
            )

        case .collection:
            .send(.entryViewLayout(.internal(.setCollectionMode(true))))
        }
    }

    func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        let forwardedAction = FileManagerContentAction.entryViewLayout(.entryOperations(action))
        return .send(forwardedAction)
    }

    func makeEntryOperationsCommandContext(state: State) -> EntryOperationsCommandContext {
        EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: state.entryViewLayout.entries,
            currentPath: state.navigation.currentPath,
        )
    }
}

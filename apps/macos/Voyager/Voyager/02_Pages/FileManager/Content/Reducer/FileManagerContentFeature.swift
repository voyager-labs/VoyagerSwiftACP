import ComposableArchitecture
import VoyagerShared

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerComputerNameClient)
    private var computerNameClient
    @Dependency(\.thumbnailGeneratorClient)
    private var thumbnailGeneratorClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Reduce { state, action in
            if let effect = handleEntryAppearanceAction(action, state: &state) {
                return effect
            }

            if let effect = handleEntryViewLayoutDelegateBridgeAction(action, state: &state) {
                return effect
            }

            if let effect = handleEntryOperationsBridgeAction(action, state: &state) {
                return effect
            }

            if let effect = handleEntryThumbnailAction(action, state: &state) {
                return effect
            }

            if let effect = handleComposerAction(action, state: &state) {
                return effect
            }

            if let effect = handleCollectionDraftAction(action, state: &state) {
                return effect
            }

            switch action {
            case let .applyNavigationState(navigationState):
                state.entryViewLayout.currentPath = state.navigation.currentPath
                state.entryViewLayout.savedScrollOffset = state.navigation.scrollPositions[state.navigation.currentPath]
                return applyNavigationStateEffect(navigationState, state: state)

            case .selectAllEntries:
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

            case .toggleShowHiddenFilesAndReload:
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: showHidden,
                    ),
                )

            case let .handleKeyCommand(command):
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case .openPathInNewWindow,
                 .openPathInNewTab,
                 .closeWindow:
                return .none

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .none

            case let .saveScrollOffset(offset, forPath: path):
                state.navigation.scrollPositions[path] = offset
                if path == state.navigation.currentPath {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            default:
                return .none
            }
        }
    }

    private func handleEntryAppearanceAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entries(entryAction) = action else {
            return nil
        }

        switch entryAction {
        case let .setListIconSize(size):
            state.listIconSize = size
            return .none

        case let .setGridIconSize(size):
            state.gridIconSize = size
            return .none

        case let .setListTextSize(size):
            state.listTextSize = size
            return .none

        case let .setGridTextSize(size):
            state.gridTextSize = size
            return .none

        default:
            return nil
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
            return .send(.entryViewLayout(.entryOperations(.executeCommand(
                command: command,
                context: makeEntryOperationsCommandContext(state: state),
            ))))

        case let .saveScrollOffset(offset, path):
            return .send(.saveScrollOffset(offset, forPath: path))

        case let .openPathInNewTab(path):
            return .send(.openPathInNewTab(path))

        case let .startRename(id, text):
            return .send(.entryViewLayout(.entryOperations(.startRename(id: id, text: text))))
        }
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .operationFinished:
            .merge(
                .send(.entryViewLayout(.entryArrangements(.reapply))),
                reloadEntryItemsEffect(state: state),
            )

        case .emptyTrashCompleted:
            .send(.closeWindow)

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
            .send(.entryViewLayout(.entryOperations(.loadItems(path: path, showHidden: showHidden))))
        case .recents:
            .send(.entryViewLayout(.entryOperations(.loadRecentItems(showHidden: showHidden))))
        case let .tags(tagName):
            .send(.entryViewLayout(.entryOperations(.loadTagItems(tagName: tagName, showHidden: showHidden))))
        case .computer:
            .send(.entryViewLayout(.entryOperations(.loadComputerItems)))
        case .collection:
            .none
        }
    }

    private func handleEntryThumbnailAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entries(entryAction) = action else {
            return nil
        }

        return FileManagerContentThumbnailCoordinator.reduce(
            entryAction,
            state: &state,
            dependencies: .init(
                thumbnailGeneratorClient: thumbnailGeneratorClient,
                entryThumbnailCacheClient: entryThumbnailCacheClient,
            ),
        )
    }

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
                computerNameClient: computerNameClient,
            ),
        )
    }

    private func handleCollectionDraftAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case .discardCollectionChanges,
             .collectionDraft(.discardChangesTapped):
            state.restoreCollectionDraftFromBaseline()

        default:
            nil
        }
    }
}

private extension FileManagerContentFeature {
    private func handleEntryOperationsDelegateAction(_ action: Action) -> Effect<Action>? {
        guard case let .entryViewLayout(.entryOperations(.delegate(delegate))) = action else {
            return nil
        }

        switch delegate {
        case let .navigateToPath(path):
            return .send(.requestNavigation(.view(.navigateToPath(path))))

        case let .openCollectionFile(url):
            return .send(.requestNavigation(.view(.openCollectionFile(url))))
        }
    }

    private func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            .merge(
                .send(.entryViewLayout(.entryOperations(.setCollectionMode(false)))),
                .send(.entryViewLayout(.entryOperations(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                )))),
            )

        case .recents:
            .merge(
                .send(.entryViewLayout(.entryOperations(.setCollectionMode(false)))),
                .send(.entryViewLayout(.entryOperations(.loadRecentItems(showHidden: state.entryViewLayout
                        .showHiddenFiles)))),
            )

        case let .tags(tagName):
            .merge(
                .send(.entryViewLayout(.entryOperations(.setCollectionMode(false)))),
                .send(.entryViewLayout(.entryOperations(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                )))),
            )

        case .computer:
            .merge(
                .send(.entryViewLayout(.entryOperations(.setCollectionMode(false)))),
                .send(.entryViewLayout(.entryOperations(.loadComputerItems))),
            )

        case .collection:
            .send(.entryViewLayout(.entryOperations(.setCollectionMode(true))))
        }
    }

    private func makeEntryOperationsCommandContext(state: State) -> EntryOperationsCommandContext {
        EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: state.entryViewLayout.entries,
            currentPath: state.navigation.currentPath,
        )
    }
}

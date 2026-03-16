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

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        Reduce { state, action in
            if let effect = handleEntryAppearanceAction(action, state: &state) {
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
                return applyNavigationStateEffect(navigationState, state: state)

            case .selectAllEntries:
                return .send(.entries(.selectAll))

            case .toggleShowHiddenFilesAndReload:
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entries(.toggleShowHiddenFiles)),
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
        guard case let .entryOperations(entryOperationsAction) = action else {
            return nil
        }

        return handleEntryOperationsAction(entryOperationsAction, state: &state)
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .itemsLoaded,
             .collectionItemsLoadedFromSearch,
             .setCollectionMode:
            .send(.entryArrangements(.reapply))

        case .operationFinished:
            .merge(
                .send(.entryArrangements(.reapply)),
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
            .send(.entryOperations(.loadItems(path: path, showHidden: showHidden)))
        case .recents:
            .send(.entryOperations(.loadRecentItems(showHidden: showHidden)))
        case let .tags(tagName):
            .send(.entryOperations(.loadTagItems(tagName: tagName, showHidden: showHidden)))
        case .computer:
            .send(.entryOperations(.loadComputerItems))
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
    private func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            .merge(
                .send(.entries(.setCollectionMode(false))),
                .send(.entryOperations(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .recents:
            .merge(
                .send(.entries(.setCollectionMode(false))),
                .send(.entryOperations(.loadRecentItems(showHidden: state.entryViewLayout.showHiddenFiles))),
            )

        case let .tags(tagName):
            .merge(
                .send(.entries(.setCollectionMode(false))),
                .send(.entryOperations(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .computer:
            .merge(
                .send(.entries(.setCollectionMode(false))),
                .send(.entryOperations(.loadComputerItems)),
            )

        case .collection:
            .send(.entries(.setCollectionMode(true)))
        }
    }
}

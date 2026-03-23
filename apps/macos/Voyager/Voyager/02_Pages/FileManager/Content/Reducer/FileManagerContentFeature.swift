import AppKit
import ComposableArchitecture
import VoyagerShared

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    fileprivate enum CancelID {
        static let systemNotifications = "FileManagerContentFeature.systemNotifications"
    }

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient: FileManagerClient
    @Dependency(\.thumbnailGeneratorClient)
    private var thumbnailGeneratorClient
    @Dependency(\.entryThumbnailCacheClient)
    private var entryThumbnailCacheClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

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
            var effect: Effect<Action>

            if let appearanceEffect = handleEntryAppearanceAction(action, state: &state) {
                effect = appearanceEffect
            } else if let bridgeEffect = handleEntryOperationsBridgeAction(action, state: &state) {
                effect = bridgeEffect
            } else if let thumbnailEffect = handleEntryThumbnailAction(action, state: &state) {
                effect = thumbnailEffect
            } else if let composerEffect = handleComposerAction(action, state: &state) {
                effect = composerEffect
            } else if let collectionDraftEffect = handleCollectionDraftAction(action, state: &state) {
                effect = collectionDraftEffect
            } else {
                switch action {
                case let .internal(.applyNavigationState(navigationState)):
                    effect = applyNavigationStateEffect(navigationState, state: state)

                case .view(.selectAllEntries):
                    let orderedIds = state.entryViewLayout.entries.map(\.id)
                    effect = .send(.entryViewLayout(.internal(.applySelectAll(orderedItemIds: orderedIds))))

                case .view(.toggleShowHiddenFilesAndReload):
                    let showHidden = !state.entryViewLayout.showHiddenFiles
                    effect = .concatenate(
                        .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                        reloadEntryItemsEffect(
                            navigationState: state.navigation.navigationState,
                            showHidden: showHidden,
                        ),
                    )

                case let .view(.handleKeyCommand(command)):
                    effect = FileManagerContentKeyCommandHandler.effect(for: command, state: state)

                case .delegate(.openPathInNewWindow),
                     .delegate(.openPathInNewTab),
                     .delegate(.closeWindow):
                    effect = .none

                case let .view(.changeLayout(layout)):
                    state.entryViewLayout.mode = layout
                    state.syncComposerCollectionState()
                    userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                    effect = .none

                case let .internal(.saveScrollOffset(offset, forPath: path)):
                    state.navigation.scrollPositions[path] = offset
                    effect = .none

                case .internal(.startObservingSystemNotifications):
                    effect = .run { send in
                        for await _ in await notificationCenterClient.notifications(
                            NSApplication.didBecomeActiveNotification,
                            nil,
                        ) {
                            await send(.internal(.systemAppDidBecomeActive))
                        }
                    }
                    .cancellable(id: CancelID.systemNotifications, cancelInFlight: true)

                case .internal(.stopObservingSystemNotifications):
                    effect = .cancel(id: CancelID.systemNotifications)

                case .internal(.systemAppDidBecomeActive):
                    effect = .send(.entryViewLayout(.entryOperations(.lifecycle(.appDidBecomeActive))))

                default:
                    effect = .none
                }
            }

            return effect
        }
    }

    private func handleEntryAppearanceAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entryViewLayout(.internal(.applyPreferences(prefs))) = action else {
            return nil
        }

        state.listIconSize = prefs.listIconSize
        state.gridIconSize = prefs.gridIconSize
        state.listTextSize = prefs.listTextSize
        state.gridTextSize = prefs.gridTextSize
        return .none
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
        case .loading(.itemsLoaded),
             .loading(.collectionItemsLoadedFromSearch),
             .loading(.setCollectionMode):
            .send(.entryArrangements(.reapply))

        case .lifecycle(.operationFinished):
            .merge(
                .send(.entryArrangements(.reapply)),
                reloadEntryItemsEffect(state: state),
            )

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
            .send(.entryOperations(.loading(.loadItems(path: path, showHidden: showHidden))))
        case .recents:
            .send(.entryOperations(.loading(.loadRecentItems(showHidden: showHidden))))
        case let .tags(tagName):
            .send(.entryOperations(.loading(.loadTagItems(tagName: tagName, showHidden: showHidden))))
        case .computer:
            .send(.entryOperations(.loading(.loadComputerItems)))
        case .collection:
            .none
        }
    }

    private func handleEntryThumbnailAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let .entryOperations(entryOpsAction) = action else {
            return nil
        }

        return FileManagerContentThumbnailCoordinator.reduce(
            entryOpsAction,
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
            state.restoreCollectionDraftFromBaseline()
            return .none

        default:
            return nil
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
                .send(.entryOperations(.loading(.setCollectionMode(false)))),
                .send(.entryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                )))),
            )

        case .recents:
            .merge(
                .send(.entryOperations(.loading(.setCollectionMode(false)))),
                .send(.entryOperations(.loading(.loadRecentItems(showHidden: state.entryViewLayout.showHiddenFiles)))),
            )

        case let .tags(tagName):
            .merge(
                .send(.entryOperations(.loading(.setCollectionMode(false)))),
                .send(.entryOperations(.loading(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                )))),
            )

        case .computer:
            .merge(
                .send(.entryOperations(.loading(.setCollectionMode(false)))),
                .send(.entryOperations(.loading(.loadComputerItems))),
            )

        case .collection:
            .send(.entryOperations(.loading(.setCollectionMode(true))))
        }
    }
}

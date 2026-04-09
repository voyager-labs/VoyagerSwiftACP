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

        case let .startRename(id, text):
            let entryOperationsAction = EntryOperationsAction.edit(.startRename(id: id, text: text))
            return sendEntryOperations(entryOperationsAction)
        }
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .loading(.itemsLoaded),
             .loading(.collectionItemsLoadedFromSearch),
             .loading(.setCollectionMode):
            .send(.entryViewLayout(.entryArrangements(.reapply)))

        case .lifecycle(.operationFinished):
            .merge(
                .send(.entryViewLayout(.entryArrangements(.reapply))),
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
                  state.entryViewLayout.entryOperations.isCollectionMode,
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

private extension FileManagerContentFeature {
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
            let clearCollectionMode = EntryOperationsAction.loading(.setCollectionMode(false))
            let loadItems = EntryOperationsAction.loading(.loadItems(
                path: path,
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))
            return .merge(
                sendEntryOperations(clearCollectionMode),
                sendEntryOperations(loadItems),
            )

        case .recents:
            let clearCollectionMode = EntryOperationsAction.loading(.setCollectionMode(false))
            let loadRecents = EntryOperationsAction.loading(.loadRecentItems(
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))
            return .merge(
                sendEntryOperations(clearCollectionMode),
                sendEntryOperations(loadRecents),
            )

        case let .tags(tagName):
            let clearCollectionMode = EntryOperationsAction.loading(.setCollectionMode(false))
            let loadTagItems = EntryOperationsAction.loading(.loadTagItems(
                tagName: tagName,
                showHidden: state.entryViewLayout.showHiddenFiles,
            ))
            return .merge(
                sendEntryOperations(clearCollectionMode),
                sendEntryOperations(loadTagItems),
            )

        case .computer:
            let clearCollectionMode = EntryOperationsAction.loading(.setCollectionMode(false))
            let loadComputerItems = EntryOperationsAction.loading(.loadComputerItems)
            return .merge(
                sendEntryOperations(clearCollectionMode),
                sendEntryOperations(loadComputerItems),
            )

        case .collection:
            let enableCollectionMode = EntryOperationsAction.loading(.setCollectionMode(true))
            return sendEntryOperations(enableCollectionMode)
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

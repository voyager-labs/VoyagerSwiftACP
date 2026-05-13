import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

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
        Reduce { state, action in
            guard case let .collection(.saveCompleted(result)) = action else {
                return .none
            }
            return handleCollectionSaveCompleted(result: result, state: &state)
        }

        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.collection, action: \.collection) {
            CollectionFeature()
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

            if let effect = handleCollectionOwnerAction(action, state: &state) {
                return effect
            }

            switch action {
            case let .internal(.applyNavigationState(navigationState)):
                if !navigationState.isCollection {
                    state.entryViewLayout.currentPath = state.navigation.currentPath
                    state.entryViewLayout.savedScrollOffset = state.navigation
                        .scrollPositions[state.navigation.currentPath]
                }
                return applyNavigationStateEffect(navigationState, state: state)

            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

            case .view(.refreshStaleCollection):
                guard state.collection.refreshBlockingReason(
                    isCollectionMode: state.isCollectionMode,
                    isDirty: state.collection.isDirty,
                    isSearching: state.composer.isCollectionSearching,
                ) == nil else {
                    return .none
                }
                let trimmedQuery = state.collection.collectionContext?
                    .query
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if trimmedQuery.isEmpty {
                    return .concatenate(
                        .send(.collection(.refreshRequested)),
                        .send(.composer(.applyFilters)),
                    )
                }

                return .concatenate(
                    .send(.collection(.refreshRequested)),
                    .send(.composer(.setText(trimmedQuery))),
                    .send(.composer(.submit)),
                )

            case .view(.toggleShowHiddenFilesAndReload):
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    FileManagerContentEntryOpsCoordinator.reloadEntryItemsEffect(
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
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .concatenate(
                    syncComposerCollectionStateEffect(state),
                    isModeChanging && hasActiveRename
                        ? .send(.entryViewLayout(.entryOperations(.edit(.cancelRename))))
                        : .none,
                )

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

            case .internal(.resetComposer):
                return resetComposerAndSyncEffect(state)

            case .internal(.resetComposerAfterDirectoryNavigation):
                guard state.resetComposerOnNextDirectoryNavigation else {
                    return .none
                }
                state.resetComposerOnNextDirectoryNavigation = false
                return resetComposerAndSyncEffect(state)

            case .internal(.clearCollectionMode), .internal(.exitCollectionMode):
                return handleCollectionModeAction(
                    action,
                    state: &state,
                    computerName: fileManagerClient.displayName("/"),
                )

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
        return FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            entryOperationsAction,
            state: &state,
        )
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
            ),
        )
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
            .none
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

import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerContentNavigationBridgeReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    private enum CancelID {
        static let systemNotifications = "FileManagerContent.systemNotifications"
    }

    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            // Bridge: entry view layout delegate → navigation / entry operations
            if let effect = handleEntryViewLayoutDelegateBridgeAction(action, state: &state) {
                return effect
            }

            // Bridge: entry operations → coordinator / metrics / navigation
            if let effect = handleEntryOperationsBridgeAction(action, state: &state) {
                return effect
            }

            switch action {
            // Navigation state application
            case let .internal(.applyNavigationState(navigationState)):
                if !navigationState.isCollection {
                    state.entryViewLayout.currentPath = state.navigation.currentPath
                    state.entryViewLayout.savedScrollOffset = state.navigation
                        .scrollPositions[state.navigation.currentPath]
                }
                return applyNavigationStateEffect(navigationState, state: state)

            // View actions
            case .view(.selectAllEntries):
                return .send(.entryViewLayout(.internal(.applySelectAll(
                    orderedItemIds: state.entryViewLayout.entries.map(\.id),
                ))))

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

            // Delegate pass-through (navigation-related)
            case .delegate(.openPathInNewWindow),
                 .delegate(.openPathInNewTab),
                 .delegate(.closeWindow):
                return .none

            // Drop item bridging → entry operations
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

            // Scroll position management
            case let .internal(.saveScrollOffset(offset, forPath: path)):
                state.navigation.scrollPositions[path] = offset
                if path == state.navigation.currentPath {
                    state.entryViewLayout.savedScrollOffset = offset
                }
                return .none

            // System notification observation lifecycle
            case .internal(.startObservingSystemNotifications):
                return .run { send in
                    for await _ in await notificationCenterClient.notifications(
                        NSApplication.didBecomeActiveNotification,
                        nil,
                    ) {
                        await send(.internal(.systemAppDidBecomeActive))
                    }
                }
                .cancellable(id: CancelID.systemNotifications, cancelInFlight: true)

            case .internal(.stopObservingSystemNotifications):
                return .cancel(id: CancelID.systemNotifications)

            case .internal(.systemAppDidBecomeActive):
                let entryOperationsAction = EntryOperationsAction.lifecycle(.appDidBecomeActive)
                return sendEntryOperations(entryOperationsAction)

            default:
                return .none
            }
        }
    }

    // MARK: - Entry View Layout Delegate Bridge

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

    // MARK: - Entry Operations Bridge

    private func handleEntryOperationsBridgeAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        // Bridge entry operations delegate → navigation
        if case let .entryViewLayout(.entryOperations(.delegate(delegate))) = action {
            switch delegate {
            case let .navigateToPath(path):
                let navigationAction: ContentPageNavigationAction = .view(.navigateToPath(path))
                return .send(.internal(.requestNavigation(navigationAction)))

            case let .openCollectionFile(url):
                let navigationAction: ContentPageNavigationAction = .view(.openCollectionFile(url))
                return .send(.internal(.requestNavigation(navigationAction)))
            }
        }

        // Bridge entry operations actions → metrics + coordinator
        guard case let .entryViewLayout(.entryOperations(entryOperationsAction)) = action else {
            return nil
        }

        FileManagerContentFeature.logEntryActionMetricIfNeeded(for: entryOperationsAction)
        return FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            entryOperationsAction,
            state: &state,
        )
    }

    // MARK: - Navigation State Application

    private func applyNavigationStateEffect(
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

    // MARK: - Helpers

    private func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        .send(.entryViewLayout(.entryOperations(action)))
    }

    private func makeEntryOperationsCommandContext(state: State) -> EntryOperationsCommandContext {
        EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: state.entryViewLayout.entries,
            currentPath: state.navigation.currentPath,
        )
    }
}

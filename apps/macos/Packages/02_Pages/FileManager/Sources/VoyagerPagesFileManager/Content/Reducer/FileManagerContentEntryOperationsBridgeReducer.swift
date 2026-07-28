import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerContentEntryOperationsBridgeReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.metricsClient)
    var metricsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            // Bridge: entry view layout delegate → entry operations
            if let effect = handleEntryViewLayoutDelegateBridgeAction(action, state: &state) {
                return effect
            }

            // Bridge: entry operations → coordinator / metrics / navigation
            if let effect = handleEntryOperationsBridgeAction(action, state: &state) {
                return effect
            }

            return .none
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
                context: makeEntryOperationsCommandContext(command: command, state: state),
            ))
            return sendEntryOperations(entryOperationsAction)

        case let .saveScrollOffset(offset, path):
            return .send(.internal(.saveScrollOffset(offset, forPath: path)))

        case let .openPathInNewWindow(path):
            return .send(.delegate(.openPathInNewWindow(path)))

        case let .startRename(item, text):
            let entryOperationsAction = EntryOperationsAction.edit(.startRename(item: item, text: text))
            return sendEntryOperations(entryOperationsAction)

        case .selectionChanged:
            let currentContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state)
            return .concatenate(
                sendEntryOperations(.lifecycle(.syncSelectedEntryIDs(state.entryViewLayout.selectedIds))),
                .send(.delegate(.currentContextChanged(currentContext))),
            )
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

            case .folderLoadEvent, .folderLoadFinished, .folderLoadFailed:
                return nil
            }
        }

        // Bridge entry operations actions → metrics + coordinator
        guard case let .entryViewLayout(.entryOperations(entryOperationsAction)) = action else {
            return nil
        }

        FileManagerContentFeature.logEntryActionMetricIfNeeded(for: entryOperationsAction, metricsClient: metricsClient)
        return FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
            entryOperationsAction,
            state: &state,
        )
    }

    // MARK: - Helpers

    private func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        .send(.entryViewLayout(.entryOperations(action)))
    }

    private func makeEntryOperationsCommandContext(
        command: EntryOperationsCommand,
        state: State,
    ) -> EntryOperationsCommandContext {
        let displayItems = switch command {
        case .mutation(.emptyTrash):
            state.entryViewLayout.entries
        default:
            state.entryViewLayout.entries
        }

        return EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: displayItems,
            currentPath: state.navigation.currentPath,
        )
    }
}

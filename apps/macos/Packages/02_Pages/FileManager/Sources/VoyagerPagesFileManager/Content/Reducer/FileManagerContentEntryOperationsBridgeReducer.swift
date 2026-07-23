import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
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
            guard let entryCommand = entryOperationsCommand(from: command, currentPath: state.navigation.currentPath)
            else {
                return .none
            }
            let entryOperationsAction = EntryOperationsAction.routing(.executeCommand(
                command: entryCommand,
                context: makeEntryOperationsCommandContext(command: entryCommand, state: state),
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
                .send(.entryOperations(.lifecycle(.syncSelectedEntryIDs(state.entryViewLayout.selectedIds)))),
                .send(.delegate(.currentContextChanged(currentContext))),
            )

        case let .expandRequested(id):
            let request = EntryFolderLoadRequest(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
                folderGeneration: 0,
                path: id,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: .none,
            )
            return .send(.entryOperations(.loading(.loadFolderItems(request))))

        case let .collapseRequested(id):
            let requestID = EntryFolderLoadRequest.RequestID(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
            )
            return .send(.entryOperations(.loading(.cancelFolderItems(requestID))))

        case let .retryRequested(id):
            let request = EntryFolderLoadRequest(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
                folderGeneration: 0,
                path: id,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: .none,
            )
            return .send(.entryOperations(.loading(.loadFolderItems(request))))

        case let .sortChanged(sortKey, sortOrder):
            let featureSortKey = sortKey.sharedSortKey
            return .concatenate(
                .send(.entryArrangements(.setSortKey(featureSortKey))),
                .send(.entryArrangements(.setSortOrder(sortOrder))),
            )

        case let .groupChanged(groupKey):
            guard let featureGroupKey = GroupKey(rawValue: groupKey.rawValue) else { return .none }
            return .send(.entryArrangements(.setGroupKey(featureGroupKey)))

        case let .renameCommitted(_, newName):
            return .concatenate(
                .send(.entryOperations(.edit(.updateRenamingText(newName)))),
                .send(.entryOperations(.edit(.commitRename))),
            )

        case let .openEntry(entry):
            return .send(.entryOperations(.open(.openFiles(paths: [entry.fullPath]))))
        }
    }

    // MARK: - Entry Operations Bridge

    private func handleEntryOperationsBridgeAction(
        _ action: Action,
        state: inout State,
    ) -> Effect<Action>? {
        // Bridge entry operations delegate → navigation
        if case let .entryOperations(.delegate(delegate)) = action {
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
        guard case let .entryOperations(entryOperationsAction) = action else {
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
        .send(.entryOperations(action))
    }

    private func makeEntryOperationsCommandContext(
        command: EntryOperationsCommand,
        state: State,
    ) -> EntryOperationsCommandContext {
        let displayItems = switch command {
        case .mutation(.emptyTrash):
            state.entryViewLayout.entries
        default:
            state.entryViewLayout.hierarchyProjectionIsActive
                ? state.entryViewLayout.visibleSelectableEntries(isNormalDirectoryPage: true)
                : state.entryViewLayout.entries
        }

        return EntryOperationsCommandContext(
            selectedIds: state.entryViewLayout.selectedIds,
            displayItems: displayItems,
            currentPath: state.navigation.currentPath,
        )
    }

    private func entryOperationsCommand(from command: String, currentPath: String) -> EntryOperationsCommand? {
        let parts = command.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let category = String(parts[0])
        let action = String(parts[1])

        switch category {
        case "navigation":
            switch action {
            case "openSelectedItem": return .navigation(.openSelectedItem)
            case "quickLookSelectedItem": return .navigation(.quickLookSelectedItem)
            default: return nil
            }

        case "clipboard":
            switch action {
            case "cutSelectedItems": return .clipboard(.cutSelectedItems)
            case "copySelectedItems": return .clipboard(.copySelectedItems)
            case "pasteItems": return .clipboard(.pasteItems(destinationPath: currentPath))
            case "duplicateSelectedItems": return .clipboard(.duplicateSelectedItems)
            case "copySelectedAbsolutePaths": return .clipboard(.copySelectedAbsolutePaths)
            case "copySelectedURLs": return .clipboard(.copySelectedURLs)
            default: return nil
            }

        case "mutation":
            switch action {
            case "emptyTrash": return .mutation(.emptyTrash)
            case "deleteSelectedItemsImmediately": return .mutation(.deleteSelectedItemsImmediately)
            case "moveSelectedItemsToTrash": return .mutation(.moveSelectedItemsToTrash)
            case "createAliasForSelectedItems": return .mutation(.createAliasForSelectedItems)
            default: return nil
            }

        default:
            return nil
        }
    }
}

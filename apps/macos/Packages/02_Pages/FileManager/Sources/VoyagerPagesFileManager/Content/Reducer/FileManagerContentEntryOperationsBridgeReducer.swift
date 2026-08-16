import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

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
        if let effect = handleOperationIntentDelegate(delegateAction, state: &state) { return effect }
        if let effect = handlePresentationLifecycleDelegate(delegateAction, state: &state) { return effect }
        return handleHierarchyDelegate(delegateAction, state: &state)
    }

    private func handleOperationIntentDelegate(
        _ delegateAction: EntryViewLayoutAction.Delegate,
        state: inout State,
    ) -> Effect<Action>? {
        switch delegateAction {
        case let .executeCommand(command):
            guard let entryCommand = entryOperationsCommand(from: command, currentPath: state.navigation.currentPath)
            else { return .none }
            let entryOperationsAction = EntryOperationsAction.routing(.executeCommand(
                command: entryCommand,
                context: makeEntryOperationsCommandContext(command: entryCommand, state: state),
            ))
            return sendEntryOperations(entryOperationsAction)

        case let .openEntry(entry):
            let command = EntryOperationsCommand.navigation(.openSelectedItem)
            return sendEntryOperations(.routing(.executeCommand(
                command: command,
                context: EntryOperationsCommandContext(
                    selectedIds: [entry.id],
                    displayItems: [entry],
                    currentPath: state.navigation.currentPath,
                ),
            )))

        case let .openWithApp(bundleID):
            let command = EntryOperationsCommand.navigation(.openWithSelectedItem(
                bundleID: bundleID, shouldSetAsDefault: false,
            ))
            return sendEntryOperations(.routing(.executeCommand(
                command: command,
                context: makeEntryOperationsCommandContext(command: command, state: state),
            )))

        case let .preloadOpenWithApplications(entries):
            return sendEntryOperations(.openWith(.loadCommonApplicationsForFiles(files: entries)))

        case let .dropItems(sourcePaths, destinationPath, isOptionDrag):
            return sendEntryOperations(.routing(.dropItems(
                sourcePaths: sourcePaths,
                destinationPath: destinationPath,
                isOptionDrag: isOptionDrag,
            )))

        default:
            return handleMutationIntentDelegate(delegateAction, state: &state)
        }
    }

    private func handleMutationIntentDelegate(
        _ delegateAction: EntryViewLayoutAction.Delegate,
        state: inout State,
    ) -> Effect<Action>? {
        switch delegateAction {
        case let .startRename(item, text):
            return sendEntryOperations(.edit(.startRename(item: item, text: text)))

        case let .renameCommitted(_, newName):
            return .concatenate(
                sendEntryOperations(.edit(.updateRenamingText(newName))),
                sendEntryOperations(.edit(.commitRename)),
            )

        case .renameCanceled:
            return sendEntryOperations(.edit(.cancelRename))

        case let .tagMutation(tagName, mode):
            let paths = selectedItemPaths(in: state)
            let featureMode: TagMutationRequest.Mode = mode == .add ? .add : .remove
            return sendEntryOperations(.tagging(.requestTagMutation(
                request: .init(mode: featureMode, tagName: tagName, paths: paths),
            )))

        case let .toggleTag(tagName):
            let paths = selectedItemPaths(in: state)
            return sendEntryOperations(.tagging(.requestTagMutation(
                request: .init(mode: .toggle, tagName: tagName, paths: paths),
            )))

        default:
            return nil
        }
    }

    private func handlePresentationLifecycleDelegate(
        _ delegateAction: EntryViewLayoutAction.Delegate,
        state: inout State,
    ) -> Effect<Action>? {
        switch delegateAction {
        case let .saveScrollOffset(offset, path):
            return .send(.internal(.saveScrollOffset(offset, forPath: path)))

        case let .openPathInNewWindow(path):
            return .send(.delegate(.openPathInNewWindow(path)))

        case let .openInNewTab(paths):
            return .send(.delegate(.openInNewTab(paths)))

        case .selectionChanged:
            let currentContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state)
            return .concatenate(
                .send(.entryViewLayout(.entryOperations(.lifecycle(.syncSelectedEntryIDs(state.entryViewLayout
                        .selectedIds))))),
                .send(.delegate(.currentContextChanged(currentContext))),
            )

        case let .sortChanged(sortKey, sortOrder):
            let featureSortKey = sortKey.sharedSortKey
            return .concatenate(
                .send(.entryViewLayout(.entryArrangements(.setSortKey(featureSortKey)))),
                .send(.entryViewLayout(.entryArrangements(.setSortOrder(sortOrder)))),
            )

        case let .groupChanged(groupKey):
            guard let featureGroupKey = GroupKey(rawValue: groupKey.rawValue) else { return .none }
            return .send(.entryViewLayout(.entryArrangements(.setGroupKey(featureGroupKey))))

        case let .toggleGroup(groupName):
            return .send(.entryViewLayout(.entryArrangements(.toggleCollapsedGroup(groupName))))

        default:
            return nil
        }
    }

    private func handleHierarchyDelegate(
        _ delegateAction: EntryViewLayoutAction.Delegate,
        state: inout State,
    ) -> Effect<Action>? {
        switch delegateAction {
        case let .expandRequested(id):
            guard let folderGeneration = state.entryViewLayout.hierarchy.nodesByID[id]?.generation
            else { return .none }
            let priority = FileManagerContentEntryOpsCoordinator
                .rootMetadataPriority(for: state.entryViewLayout.entryArrangements)
            return sendEntryOperations(.loading(.loadFolderItems(.init(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
                folderGeneration: folderGeneration,
                path: id,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: priority,
                ancestorPaths: lexicalAncestorPaths(for: id, state: state),
            ))))

        case let .collapseRequested(id):
            return sendEntryOperations(.loading(.cancelFolderItems(.init(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
            ))))

        case .rootContextChanged:
            return sendEntryOperations(.loading(.cancelAllFolderItems))

        case let .retryRequested(id):
            guard let folderGeneration = state.entryViewLayout.hierarchy.nodesByID[id]?.generation
            else { return .none }
            let priority = FileManagerContentEntryOpsCoordinator
                .rootMetadataPriority(for: state.entryViewLayout.entryArrangements)
            return sendEntryOperations(.loading(.loadFolderItems(.init(
                rootContextGeneration: state.entryViewLayout.hierarchy.rootContextGeneration,
                folderID: id,
                folderGeneration: folderGeneration,
                path: id,
                showHidden: state.entryViewLayout.showHiddenFiles,
                priority: priority,
                ancestorPaths: lexicalAncestorPaths(for: id, state: state),
            ))))

        default:
            return nil
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

            case let .openInNewTab(paths):
                return .send(.delegate(.openInNewTab(paths)))

            case let .folderLoadEvent(request, event):
                return .send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
                    rootContextGeneration: request.id.rootContextGeneration,
                    folderID: request.id.folderID,
                    folderGeneration: request.folderGeneration,
                    .event(event),
                ))))

            case let .folderLoadFinished(request):
                return .send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
                    rootContextGeneration: request.id.rootContextGeneration,
                    folderID: request.id.folderID,
                    folderGeneration: request.folderGeneration,
                    .streamCompleted,
                ))))

            case let .folderLoadFailed(request, failure):
                let entryLoadFailure: EntryLoadFailure = switch failure {
                case .permissionDenied:
                    .permissionDenied
                case let .unavailable(description):
                    .unavailable(description: description)
                }
                return .send(.entryViewLayout(.hierarchy(.folderChildrenResponse(
                    rootContextGeneration: request.id.rootContextGeneration,
                    folderID: request.id.folderID,
                    folderGeneration: request.folderGeneration,
                    .failed(entryLoadFailure),
                ))))
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
        case "navigation": return navigationCommand(action: action, currentPath: currentPath)
        case "clipboard": return clipboardCommand(action: action, currentPath: currentPath)
        case "mutation": return mutationCommand(action: action)
        default: return nil
        }
    }

    private func navigationCommand(action: String, currentPath: String) -> EntryOperationsCommand? {
        switch action {
        case "openSelectedItem": .navigation(.openSelectedItem)
        case "quickLookSelectedItem": .navigation(.quickLookSelectedItem)
        case "getInfoForSelectedItems": .navigation(.getInfoForSelectedItems)
        case "getInfoForPath": .navigation(.getInfoForPath(currentPath))
        case "shareSelectedItems": .navigation(.shareSelectedItems(anchor: nil))
        case "revealSelectedItemsInFinder": .navigation(.revealSelectedItemsInFinder)
        default: nil
        }
    }

    private func clipboardCommand(action: String, currentPath: String) -> EntryOperationsCommand? {
        switch action {
        case "cutSelectedItems": .clipboard(.cutSelectedItems)
        case "copySelectedItems": .clipboard(.copySelectedItems)
        case "pasteItems": .clipboard(.pasteItems(destinationPath: currentPath))
        case "duplicateSelectedItems": .clipboard(.duplicateSelectedItems)
        case "copySelectedAbsolutePaths": .clipboard(.copySelectedAbsolutePaths)
        case "copySelectedURLs": .clipboard(.copySelectedURLs)
        default: nil
        }
    }

    private func mutationCommand(action: String) -> EntryOperationsCommand? {
        switch action {
        case "emptyTrash": .mutation(.emptyTrash)
        case "deleteSelectedItemsImmediately": .mutation(.deleteSelectedItemsImmediately)
        case "moveSelectedItemsToTrash": .mutation(.moveSelectedItemsToTrash)
        case "createAliasForSelectedItems": .mutation(.createAliasForSelectedItems)
        case "compressSelectedItems": .mutation(.compressSelectedItems)
        case "extractSelectedItem": .mutation(.extractSelectedItem)
        case "putBackSelectedItems": .mutation(.putBackSelectedItems)
        default: nil
        }
    }

    private func selectedItemPaths(in state: State) -> [String] {
        let displayItems = state.entryViewLayout.hierarchyProjectionIsActive
            ? state.entryViewLayout.visibleSelectableEntries(isNormalDirectoryPage: true)
            : state.entryViewLayout.entries
        return displayItems
            .filter { state.entryViewLayout.selectedIds.contains($0.id) }
            .map(\.fullPath)
    }

    private func lexicalAncestorPaths(for id: EntryModel.ID, state: State) -> [String] {
        var ancestors: [String] = []
        var visitedIDs: Set<EntryModel.ID> = [id]
        var currentID = id

        while let parentID = state.entryViewLayout.hierarchy.nodesByID[currentID]?.parentID,
              visitedIDs.insert(parentID).inserted
        {
            ancestors.append(parentID)
            currentID = parentID
        }

        let rootPath = state.entryViewLayout.hierarchy.rootPath
        if !rootPath.isEmpty, visitedIDs.insert(rootPath).inserted {
            ancestors.append(rootPath)
        }
        return ancestors.reversed()
    }
}

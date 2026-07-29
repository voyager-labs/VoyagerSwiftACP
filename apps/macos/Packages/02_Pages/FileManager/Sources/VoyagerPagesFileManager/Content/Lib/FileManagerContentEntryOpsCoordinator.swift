import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations

enum FileManagerContentEntryOpsCoordinator {
    static func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case let .loading(.itemsLoaded(entries)):
            handleItemsLoaded(entries: entries, state: &state)

        case let .lifecycle(.entryActionCompleted(record)):
            .merge(
                handleEntryActionCompleted(record, state: state),
                record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
            )

        case let .undoRedo(.entryActionApplied(direction: direction, record: record)):
            .merge(
                handleEntryActionApplied(direction: direction, record: record, state: state),
                record.operationKind == .setTags ? setTagsRefreshEffect(record: record, state: state) : .none,
            )

        case let .lifecycle(.pathsMutated(paths)):
            handleMutatedPaths(paths, removedPrefixes: [], state: state)

        case let .lifecycle(.operationFinished(path, kind, result)):
            handleOperationFinished(path: path, kind: kind, result: result, state: state)

        case .lifecycle(.emptyTrashCompleted):
            .send(.delegate(.closeWindow))

        default:
            .none
        }
    }

    static func reloadEntryItemsEffect(state: FileManagerContentState) -> Effect<FileManagerContentAction> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
            priority: rootMetadataPriority(for: state.entryViewLayout.entryArrangements),
        )
    }

    static func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
        priority: EntryMetadataPriority = .none,
    ) -> Effect<FileManagerContentAction> {
        switch navigationState {
        case .home:
            .none
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(
                path: path,
                showHidden: showHidden,
                priority: priority,
            )))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(
                showHidden: showHidden,
                priority: priority,
            )))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: showHidden,
                priority: priority,
            )))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection, .aiChat, .aiChatSessions:
            .none
        }
    }

    /// itemsLoaded reconcile 전에 pending selection을 동기 반영한다.
    @discardableResult
    static func applyPendingSelectionForLoadedEntries(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Bool {
        guard let selectID = state.pendingSelectEntryID else { return false }
        let normalizedSelectID = normalizedPath(selectID)
        guard let matchedID = entries.first(where: { normalizedPath($0.id) == normalizedSelectID })?.id else {
            return false
        }

        let selectedIds = Set([matchedID])
        let didChangeSelection = state.entryViewLayout.selectedIds != selectedIds
        state.pendingSelectEntryID = nil
        state.entryViewLayout.selectedIds = selectedIds
        state.entryViewLayout.lastSelectedId = matchedID
        state.entryViewLayout.rangeAnchorId = matchedID
        state.entryViewLayout.shouldScrollToSelection = true
        return didChangeSelection
    }

    static func rootMetadataPriority(
        for arrangements: EntryArrangementsFeature.State,
    ) -> EntryMetadataPriority {
        rootMetadataPriority(
            sortKey: arrangements.sortKey,
            groupKey: arrangements.groupKey,
        )
    }

    static func rootMetadataPriority(
        sortKey: SortKey,
        groupKey: GroupKey,
    ) -> EntryMetadataPriority {
        let probes = [
            metadataProbe(for: sortKey),
            metadataProbe(for: groupKey),
        ].compactMap(\.self)
        return probes.isEmpty ? .none : .active(probes)
    }

    private static func setTagsRefreshEffect(
        record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState else {
            return reloadEntryItemsEffect(state: state)
        }
        let successfulPaths = record.targets.compactMap(\.afterPath)
        guard !successfulPaths.isEmpty else { return .none }
        return .concatenate(
            .send(.collection(.externalPathsChanged(successfulPaths))),
            .send(.view(.refreshStaleCollection)),
        )
    }

    private static func handleEntryActionCompleted(
        _ record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if case let .folder(currentPath) = state.navigation.navigationState,
           let updatedRootPath = record.targets.first(where: {
               $0.beforePath.map { pathsEqual($0, currentPath) } == true && $0.afterPath != nil
           })?.afterPath
        {
            return .send(.internal(.requestNavigation(.view(.navigateToPath(updatedRootPath)))))
        }

        if case .folder = state.navigation.navigationState {
            let affectedPaths = record.targets.flatMap { target in
                [target.beforePath, target.afterPath].compactMap(\.self)
            }
            let removedPrefixes = record.operationKind.sourcePathCeasesToExistAtOriginalLocation
                ? record.targets.compactMap(\.beforePath)
                : []
            guard !affectedPaths.isEmpty else { return .none }
            return .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths: affectedPaths.map(parentPath(for:)),
                removedPrefixes: removedPrefixes,
            ))))
        }

        guard case .collection = state.navigation.navigationState,
              record.operationKind == .putBack
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.afterPath),
            state: state,
        )
    }

    private static func handleEntryActionApplied(
        direction: EntryActionDirection,
        record: EntryActionRecord,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard case .collection = state.navigation.navigationState,
              direction == .undo,
              record.operationKind == .moveToTrash
        else {
            return .none
        }

        return restoreCollectionPathsEffect(
            record.targets.compactMap(\.beforePath),
            state: state,
        )
    }

    private static func restoreCollectionPathsEffect(
        _ restoredPaths: [String],
        state _: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard !restoredPaths.isEmpty else {
            return .none
        }
        return .send(.entryViewLayout(.internal(.addCollectionPaths(restoredPaths))))
    }

    private static func handleMutatedPaths(
        _ paths: [String],
        removedPrefixes: [String],
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch state.navigation.navigationState {
        case .folder:
            guard !paths.isEmpty else { return .none }
            return .send(.entryViewLayout(.hierarchy(.hierarchyInvalidated(
                affectedPaths: paths.map(parentPath(for:)),
                removedPrefixes: removedPrefixes,
            ))))

        case .collection:
            return .send(.entryViewLayout(.internal(.removeCollectionPaths(paths))))

        default:
            return .none
        }
    }

    private static func handleOperationFinished(
        path: String,
        kind: OperationKind,
        result: Result<Void, FileOpError>,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        let removedPathEffect: Effect<FileManagerContentAction> = if kind == .deleteImmediately,
                                                                     case .success = result
        {
            handleMutatedPaths([path], removedPrefixes: [path], state: state)
        } else {
            .none
        }
        return .merge(
            removedPathEffect,
            kind == .setTags ? .none : reloadEntryItemsEffect(state: state),
        )
    }

    /// itemsLoaded 후 pendingSelectEntryID가 있으면 해당 엔트리를 선택 focus
    private static func handleItemsLoaded(
        entries: [EntryModel],
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard applyPendingSelectionForLoadedEntries(entries: entries, state: &state) else {
            return .none
        }
        return .send(.entryViewLayout(.delegate(.selectionChanged)))
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func parentPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
    }

    private static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path
            == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static func metadataProbe(for key: SortKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    private static func metadataProbe(for key: GroupKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .none, .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    private static func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.entryOperations(action)))
    }
}

private extension OperationKind {
    var sourcePathCeasesToExistAtOriginalLocation: Bool {
        switch self {
        case .pasteFileMove, .rename, .moveToTrash, .putBack:
            true
        default:
            false
        }
    }
}

import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared

public struct EntryViewLayoutCollectionCancelID: Hashable, Sendable {
    private enum Operation: Hashable {
        case replace
        case append(Int)
    }

    private let windowID: UUID?
    private let ownerID: UUID
    private let operation: Operation

    public static func replace(windowID: UUID?, ownerID: UUID) -> Self {
        Self(windowID: windowID, ownerID: ownerID, operation: .replace)
    }

    public static func append(token: Int, windowID: UUID?, ownerID: UUID) -> Self {
        Self(windowID: windowID, ownerID: ownerID, operation: .append(token))
    }
}

@Reducer
public struct EntryViewLayoutFeature {
    public typealias State = EntryViewLayoutState
    public typealias Action = EntryViewLayoutAction

    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    public init() {}

    enum CollectionOperation: Hashable {
        case replace
        case append(Int)
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .entryOperations(.lifecycle(.entryActionCompleted(record))):
                beginIdentityReplacementFromRecord(record, state: &state)
            case let .entryOperations(.undoRedo(.replaySucceeded(
                direction: direction,
                sourceRecordID: _,
                updatedRecord: record,
            ))):
                beginIdentityReplacementFromRecord(
                    record.applying(direction: direction),
                    state: &state,
                )
            default:
                .none
            }
        }

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryThumbnail, action: \.entryThumbnail) {
            EntryThumbnailFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        EntryListHierarchyReducer()

        Reduce { state, action in
            switch action {
            case let .identityReplacement(identityAction):
                return handleIdentityReplacementAction(identityAction, state: &state)

            case let .internal(.setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                return setSelectionState(
                    ids: ids,
                    lastSelectedId: lastSelectedId,
                    rangeAnchorId: rangeAnchorId,
                    shouldScrollToSelection: shouldScrollToSelection,
                    state: &state,
                )

            case let .internal(.applySelectAll(orderedItemIds)):
                let previousSelection = state.selectedIds
                let selectedIds = Set(orderedItemIds)
                let lastSelectedId = orderedItemIds.last
                state.selectedIds = selectedIds
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = lastSelectedId
                state.shouldScrollToSelection = false
                guard previousSelection != selectedIds else { return .none }
                return .send(.delegate(.selectionChanged))

            case .internal(.applyClearSelection):
                return applyClearSelection(state: &state)

            case .internal(.reconcileHierarchySelection):
                let previousSelection = state.selectedIds
                state.reconcileSelectionWithVisibleEntries()
                var effects: [Effect<Action>] = []
                if let renamingId = state.entryOperations.renamingItemId,
                   previousSelection.contains(renamingId),
                   !state.selectedIds.contains(renamingId)
                {
                    effects.append(.send(.delegate(.renameCanceled)))
                }
                if previousSelection != state.selectedIds {
                    effects.append(.send(.delegate(.selectionChanged)))
                }
                return .merge(effects)

            case let .internal(.applySelectionOffset(offset, isShiftPressed, orderedItemIds)):
                return applySelectionOffset(
                    offset: offset,
                    isShiftPressed: isShiftPressed,
                    orderedItemIds: orderedItemIds,
                    state: &state,
                )

            case let .internal(.updateGridColumnCount(count)):
                state.gridColumnCount = max(1, count)
                return .none

            case let .internal(.setMode(mode)):
                state.mode = mode
                return .send(.internal(.reconcileHierarchySelection))

            case let .internal(.setListVisibleColumns(columns)):
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(columns)
                return .none

            case let .internal(.setListColumnVisibility(column, isVisible)):
                var nextColumns = state.listVisibleColumns
                if isVisible {
                    if !nextColumns.contains(column) {
                        nextColumns.append(column)
                    }
                } else if !EntryListColumn.requiredColumns.contains(column) {
                    nextColumns.removeAll { $0 == column }
                }
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(nextColumns)
                return .none

            case let .internal(.moveListColumn(from, to)):
                var nextColumns = EntryListColumn.normalizeVisibleColumns(state.listVisibleColumns)
                guard nextColumns.indices.contains(from) else { return .none }

                if from == to {
                    return .none
                }

                let moved = nextColumns.remove(at: from)
                let destination = max(0, min(to, nextColumns.count))
                nextColumns.insert(moved, at: destination)
                state.listVisibleColumns = EntryListColumn.normalizeVisibleColumns(nextColumns)
                return .none

            case .internal(.resetListVisibleColumns):
                state.listVisibleColumns = EntryListColumn.defaultVisibleColumns
                return .none

            case .internal(.resetScrollFlag):
                state.shouldScrollToSelection = false
                return .none

            case let .internal(.applyPreferences(preferences)):
                state.listIconSize = preferences.listIconSize
                state.listTextSize = preferences.listTextSize
                state.gridIconSize = preferences.gridIconSize
                state.gridTextSize = preferences.gridTextSize
                return Self.setShowHiddenFiles(preferences.showHiddenFiles, state: &state)

            case let .view(.setDropTargeted(isTargeted)):
                state.isDropTargeted = isTargeted
                return .none

            case let .view(.updateSelection(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                return .send(.internal(.setSelectionState(
                    ids: ids,
                    lastSelectedId: lastSelectedId,
                    rangeAnchorId: rangeAnchorId,
                    shouldScrollToSelection: shouldScrollToSelection,
                )))

            case .view(.clearSelection):
                return .send(.internal(.applyClearSelection))

            case let .view(.selectAll(orderedItemIds)):
                return .send(.internal(.applySelectAll(orderedItemIds: orderedItemIds)))

            case let .view(.updateGridColumnCount(count)):
                return .send(.internal(.updateGridColumnCount(count)))

            case let .view(.updateListVisibleColumns(columns)):
                return .send(.internal(.setListVisibleColumns(columns)))

            case let .view(.updateListColumnVisibility(column, isVisible)):
                return .send(.internal(.setListColumnVisibility(column: column, isVisible: isVisible)))

            case let .view(.moveListColumn(from, to)):
                return .send(.internal(.moveListColumn(from: from, to: to)))

            case .view(.resetListVisibleColumns):
                return .send(.internal(.resetListVisibleColumns))

            case .view(.resetScrollFlag):
                return .send(.internal(.resetScrollFlag))

            case let .internal(.selectTypeScrollTarget(id)):
                // 문자 탐색은 selection navigation이다. pending target은 물리 reveal 소비 경로만 소유하고
                // tuple 교체와 selectionChanged 발행은 setSelectionState 단일 owner에 위임한다.
                state.pendingTypeScrollTargetId = id
                return setSelectionState(
                    ids: [id],
                    lastSelectedId: id,
                    rangeAnchorId: id,
                    shouldScrollToSelection: false,
                    state: &state,
                )

            case .view(.resetTypeScrollTarget):
                state.pendingTypeScrollTargetId = nil
                return .none

            case let .view(.dropItems(sourcePaths, destinationPath, isOptionDrag)):
                return .send(.delegate(.dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionDrag,
                )))

            case let .view(.externalDropAccepted(request)):
                return .send(.entryOperations(.externalDrop(.accepted(request: request))))

            case let .view(.externalDropCancelSession(sessionID)):
                return .send(.entryOperations(.externalDrop(.cancelSession(sessionID))))

            case let .view(.executeCommand(command)):
                return .send(.delegate(.executeCommand(command)))

            case let .view(.openPathInNewWindow(path)):
                return .send(.delegate(.openPathInNewWindow(path)))

            case let .view(.openInNewTab(paths)):
                return .send(.delegate(.openInNewTab(paths)))

            case let .view(.performService(serviceName)):
                return .send(.delegate(.performService(serviceName: serviceName)))

            case let .view(.startRename(item, text)):
                return .send(.delegate(.startRename(item: item, text: text)))

            case let .view(.commitRename(itemID, newName)):
                return .send(.delegate(.renameCommitted(itemID: itemID, newName: newName)))

            case let .view(.openEntry(entry)):
                return .send(.delegate(.openEntry(entry)))

            case let .view(.saveScrollOffset(offset, path)):
                return .send(.delegate(.saveScrollOffset(offset, forPath: path)))

            case let .view(.changeSort(sortKey, sortOrder)):
                return .send(.delegate(.sortChanged(sortKey, sortOrder)))

            case let .view(.toggleGroup(groupName)):
                return .send(.delegate(.toggleGroup(groupName)))

            case let .view(.preloadOpenWithApplications(entries)):
                return .send(.delegate(.preloadOpenWithApplications(entries)))

            case let .view(.openWithApp(bundleID)):
                return .send(.delegate(.openWithApp(bundleID: bundleID)))

            case let .view(.toggleTag(tagName)):
                return .send(.delegate(.toggleTag(tagName: tagName)))

            case let .view(.mutateTag(name, mode)):
                return .send(.delegate(.tagMutation(tagName: name, mode: mode)))

            case let .view(.expandFolder(id)):
                return .send(.hierarchy(.folderExpansionRequested(id: id)))

            case let .view(.collapseFolder(id)):
                return .send(.hierarchy(.folderCollapseRequested(id: id)))

            case let .view(.retryFolder(id)):
                return .send(.hierarchy(.folderRetryRequested(id: id)))

            case .view(.openSelectedItem):
                return .send(.delegate(.executeCommand("navigation.openSelectedItem")))

            case .view(.selectNextItem),
                 .view(.selectPreviousItem),
                 .view(.selectByOffset),
                 .view(.startDrag),
                 .view(.handleDrop):
                return .none

            case let .internal(.setShowHiddenFiles(show)):
                return Self.setShowHiddenFiles(show, state: &state)

            case .view(.toggleShowHiddenFiles):
                return Self.setShowHiddenFiles(!state.showHiddenFiles, state: &state)

            case let .view(.applyContentProjection(projection)):
                let previousSelectedIds = state.selectedIds
                let replacementEffect = applyIdentityReplacementEntries(projection.entries, state: &state)
                let replacementChangedSelection = state.selectedIds != previousSelectedIds
                state.entries = projection.entries
                state.trashDirectoryPath = projection.trashDirectoryPath
                state.entryOperations.isLoading = projection.isLoading
                state.entryOperations.renamingItemId = projection.renamingItemId
                state.entryOperations.renamingText = projection.renamingText
                state.entryOperations.windowID = projection.collectionWindowID
                state.entryOperations.loadingCancellationOwnerID = projection.collectionLoadingCancellationOwnerID
                state.reconcileSelectionWithVisibleEntries(preservesScrollIntent: true)
                var reconcileEffects: [Effect<Action>] = []
                if let renamingId = state.entryOperations.renamingItemId,
                   previousSelectedIds.contains(renamingId),
                   !state.selectedIds.contains(renamingId)
                {
                    reconcileEffects.append(.send(.delegate(.renameCanceled)))
                }
                if previousSelectedIds != state.selectedIds, !replacementChangedSelection {
                    reconcileEffects.append(.send(.delegate(.selectionChanged)))
                }
                return .merge(reconcileEffects + [replacementEffect])

            case let .internal(.setCollectionMode(isCollectionMode)):
                state.isCollectionMode = isCollectionMode
                if !isCollectionMode {
                    state.isCollectionContentLoading = false
                }
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.setCollectionContentLoading(isLoading)):
                state.isCollectionContentLoading = isLoading
                return .none

            case let .internal(.setCollectionItems(items)):
                state.collectionItems = IdentifiedArrayOf(uniqueElements: items)
                state.isCollectionContentLoading = false
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.applyCollectionSearchPaths(paths, showHidden, priority)):
                return applyCollectionSearchPaths(
                    paths: paths,
                    showHidden: showHidden,
                    priority: priority,
                    state: &state,
                )

            case let .internal(.addCollectionPaths(paths)):
                return addCollectionPaths(paths, state: &state)

            case let .internal(.collectionReplaceEvent(epoch, event)):
                guard epoch == state.collectionReplaceEpoch,
                      !state.collectionStreamCompleted
                else { return .none }
                return Self.applyCollectionEvent(
                    event,
                    state: &state,
                    expectedBatchIndex: \State.expectedCollectionReplaceBatchIndex,
                )

            case let .internal(.collectionReplaceStreamCompleted(epoch)):
                guard epoch == state.collectionReplaceEpoch,
                      !state.collectionStreamCompleted
                else { return .none }
                state.collectionStreamCompleted = true
                state.activeCollectionReplacePaths = []
                return .none

            case let .internal(.collectionReplaceFailed(epoch, message)):
                guard epoch == state.collectionReplaceEpoch,
                      !state.collectionStreamCompleted
                else { return .none }
                state.collectionIncompleteFailure = message
                state.collectionStreamCompleted = true
                state.activeCollectionReplacePaths = []
                state.isCollectionContentLoading = false
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.collectionAppendEvent(epoch, token, event)):
                guard epoch == state.collectionReplaceEpoch,
                      let expectedBatchIndex = state.activeAppendExpectedBatchIndices[token]
                else { return .none }
                return Self.applyCollectionAppendEvent(
                    event,
                    token: token,
                    expectedBatchIndex: expectedBatchIndex,
                    state: &state,
                )

            case let .internal(.collectionAppendStreamCompleted(epoch, token)):
                guard epoch == state.collectionReplaceEpoch,
                      state.activeAppendExpectedBatchIndices.removeValue(forKey: token) != nil
                else { return .none }
                state.activeCollectionAppendPaths[token] = nil
                state.finishedCollectionAppendTokens.remove(token)
                return .none

            case let .internal(.collectionAppendFailed(epoch, token, message)):
                guard epoch == state.collectionReplaceEpoch,
                      state.activeAppendExpectedBatchIndices.removeValue(forKey: token) != nil
                else { return .none }
                state.activeCollectionAppendPaths[token] = nil
                state.finishedCollectionAppendTokens.remove(token)
                state.collectionIncompleteFailure = message
                return Self.updateEntriesAndReapply(&state)

            case let .internal(.removeCollectionPaths(paths)):
                guard state.isCollectionMode else { return .none }
                let mutatedPaths = Set(paths.map(Self.normalizedPath(_:)))
                guard !mutatedPaths.isEmpty else { return .none }
                state.removedCollectionPaths.formUnion(mutatedPaths)
                state.activeCollectionReplacePaths.removeAll {
                    Self.matchesAnyMutatedPath($0, mutatedPaths: mutatedPaths)
                }
                for token in state.activeCollectionAppendPaths.keys {
                    state.activeCollectionAppendPaths[token]?.removeAll {
                        Self.matchesAnyMutatedPath($0, mutatedPaths: mutatedPaths)
                    }
                }

                state.removedCollectionPaths.formUnion(mutatedPaths)

                let remainingItems = state.collectionItems.filter { item in
                    !Self.matchesAnyMutatedPath(item.fullPath, mutatedPaths: mutatedPaths)
                }
                guard remainingItems.count != state.collectionItems.count else {
                    return .none
                }

                state.collectionItems = IdentifiedArrayOf(uniqueElements: Array(remainingItems))
                return Self.updateEntriesAndReapply(&state)

            case .internal(.cancelCollectionMaterialization):
                let cancellationEffects = state.activeAppendExpectedBatchIndices.keys.map {
                    Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
                }
                let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
                state.collectionReplaceEpoch &+= 1
                state.activeCollectionReplacePaths = []
                state.expectedCollectionReplaceBatchIndex = 0
                state.activeAppendExpectedBatchIndices = [:]
                state.activeCollectionAppendPaths = [:]
                state.finishedCollectionAppendTokens = []
                state.collectionCoreFinished = false
                state.collectionStreamCompleted = false
                state.isCollectionContentLoading = false
                return .merge(cancellationEffects + [.cancel(id: replaceCancelID)])

            case .internal(.restartCollectionMaterialization):
                let replacePaths = state.activeCollectionReplacePaths
                let appendPaths = state.activeAppendExpectedBatchIndices.keys
                    .sorted()
                    .compactMap { state.activeCollectionAppendPaths[$0] }
                    .filter { !$0.isEmpty }
                guard !replacePaths.isEmpty || !appendPaths.isEmpty else { return .none }

                let showHidden = state.showHiddenFiles
                let priority = Self.collectionMetadataPriority(for: state)
                var effects: [Effect<Action>] = [
                    .send(.internal(.cancelCollectionMaterialization)),
                ]
                if !replacePaths.isEmpty {
                    effects.append(.send(.internal(.applyCollectionSearchPaths(
                        paths: replacePaths,
                        showHidden: showHidden,
                        priority: priority,
                    ))))
                }
                effects.append(contentsOf: appendPaths.map {
                    .send(.internal(.addCollectionPaths($0)))
                })
                return .concatenate(effects)

            case .internal(.clearCollectionPresentation):
                let cancellationEffects = state.activeAppendExpectedBatchIndices.keys.map {
                    Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
                }
                let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
                state.clearCollectionPresentation()
                return .merge(cancellationEffects + [
                    .cancel(id: replaceCancelID),
                    Self.updateEntriesAndReapply(&state),
                ])

            case .delegate:
                return .none

            case .entryThumbnail:
                return .none

            case let .entryOperations(entryOperationsAction):
                let replacementEffect = handleIdentityReplacementEntryOperationsAction(
                    entryOperationsAction,
                    state: &state,
                )
                switch entryOperationsAction {
                case .loading(.itemsLoaded),
                     .loading(.itemsLoadFailed):
                    return .merge(
                        Self.updateEntriesAndReapply(&state),
                        replacementEffect,
                    )
                default:
                    return replacementEffect
                }

            case let .entryArrangements(entryArrangementsAction):
                switch entryArrangementsAction {
                case .delegate(.requestApply):
                    return .send(.entryArrangements(.apply(
                        items: state.entries,
                        isCollectionMode: state.isCollectionMode,
                    )))
                case let .delegate(.applied(sortedItems, _)):
                    state.entries = sortedItems
                    return .send(.internal(.reconcileHierarchySelection))
                default:
                    return .none
                }

            case let .hierarchy(hierarchyAction):
                return handleIdentityReplacementHierarchyAction(hierarchyAction, state: &state)
            }
        }
    }

    nonisolated static func collectionCancelID(
        for operation: CollectionOperation,
        state: State,
    ) -> EntryViewLayoutCollectionCancelID {
        switch operation {
        case .replace:
            EntryViewLayoutCollectionCancelID.replace(
                windowID: state.entryOperations.windowID,
                ownerID: state.entryOperations.loadingCancellationOwnerID,
            )
        case let .append(token):
            EntryViewLayoutCollectionCancelID.append(
                token: token,
                windowID: state.entryOperations.windowID,
                ownerID: state.entryOperations.loadingCancellationOwnerID,
            )
        }
    }

    // MARK: - Helpers

    private func beginIdentityReplacementFromRecord(
        _ record: EntryActionRecord,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.isCollectionMode,
              !state.hierarchy.rootPath.isEmpty,
              record.operationKind == .rename || record.operationKind == .pasteFileMove
        else {
            return .none
        }
        let lexicalRootPath = standardizedPath(state.hierarchy.rootPath)
        let rootPath = canonicalizedPath(lexicalRootPath)
        let selectedPaths = Set(state.selectedIds.map(canonicalizedPath))
        let pairs = record.targets.compactMap { target -> EntryIdentityReplacementPair? in
            guard let beforePath = target.beforePath,
                  let afterPath = target.afterPath,
                  selectedPaths.contains(canonicalizedPath(beforePath)),
                  isSameOrDescendant(path: standardizedPath(beforePath), of: lexicalRootPath),
                  record.targets.count(where: {
                      guard let candidate = $0.beforePath else { return false }
                      return canonicalizedPath(candidate) == canonicalizedPath(beforePath)
                  }) == 1,
                  canonicalizedPath(beforePath) != canonicalizedPath(afterPath)
            else { return nil }
            return .init(
                beforePath: canonicalizedPath(beforePath),
                afterPath: canonicalizedPath(afterPath),
                beforeLexicalPath: beforePath,
                afterLexicalPath: afterPath,
            )
        }
        guard !pairs.isEmpty else { return .none }
        return handleIdentityReplacementAction(
            .begin(.init(
                transactionID: record.id,
                rootPath: canonicalizedPath(rootPath),
                pairs: pairs,
            )),
            state: &state,
        )
    }

    private func handleIdentityReplacementAction(
        _ action: EntryIdentityReplacementAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .begin(plan):
            guard !plan.pairs.isEmpty,
                  !state.hierarchy.rootPath.isEmpty,
                  canonicalizedPath(plan.rootPath) == canonicalizedPath(state.hierarchy.rootPath)
            else { return .none }
            var supersededEffect: Effect<Action> = .none
            if let existingTransactionID = state.identityReplacement?.plan.transactionID {
                supersededEffect = handleIdentityReplacementAction(
                    .cancel(id: existingTransactionID, reason: .superseded),
                    state: &state,
                )
            }
            state.identityReplacement = .init(plan: plan)
            for pair in plan.pairs {
                let beforePath = pair.beforeLexicalPath.isEmpty ? pair.beforePath : pair.beforeLexicalPath
                guard let sourceID = state.hierarchy.nodesByID.keys.first(where: {
                    standardizedPath(parentPath(for: beforePath)) == standardizedPath($0)
                }) else { continue }
                let afterPath = pair.afterLexicalPath.isEmpty ? pair.afterPath : pair.afterLexicalPath
                let destinationPath = standardizedPath(parentPath(for: afterPath))
                guard standardizedPath(sourceID) != destinationPath else { continue }
                state.identityReplacement?.sourceFolderIDs.insert(sourceID)
                state.hierarchy.beginDeferredFolderReplacement(
                    folderID: sourceID,
                    untilEntryID: afterPath,
                    holdsUntilMigration: true,
                )
            }
            return supersededEffect

        case let .cancel(id, _):
            guard state.identityReplacement?.plan.transactionID == id else { return .none }
            let previousSelection = state.selectedIds
            state.identityReplacement = nil
            state.hierarchy.commitDeferredFolderReplacementsOnCancel()
            state.reconcileSelectionWithVisibleEntries()
            guard previousSelection != state.selectedIds else { return .none }
            return .send(.delegate(.selectionChanged))

        case let .settle(id, outcome):
            return settleIdentityReplacement(id: id, outcome: outcome, state: &state)
        }
    }

    private func settleIdentityReplacement(
        id: UUID,
        outcome: EntryIdentityReplacementOutcome,
        state: inout State,
    ) -> Effect<Action> {
        guard let replacement = state.identityReplacement,
              replacement.plan.transactionID == id
        else { return .none }
        let previousSelection = state.selectedIds
        let previousLastSelectedID = state.lastSelectedId
        let previousRangeAnchorID = state.rangeAnchorId
        let previousShouldScrollToSelection = state.shouldScrollToSelection
        let completedDestinationPaths: Set<String> = if case .completed = outcome {
            Set(replacement.plan.pairs.map { pair in
                standardizedPath(pair.afterLexicalPath.isEmpty ? pair.afterPath : pair.afterLexicalPath)
            })
        } else {
            []
        }
        let completedDestinationIDs = previousSelection.filter {
            completedDestinationPaths.contains(standardizedPath($0))
        }

        state.identityReplacement = nil
        state.hierarchy.commitDeferredFolderReplacementsOnCancel()
        state.reconcileSelectionWithVisibleEntries()
        // A root reload migrates canonical selection before its projection effect applies.
        // Preserve only proven destination identities across that short stale-row window;
        // all unrelated stale selection remains subject to normal reconciliation.
        state.selectedIds.formUnion(completedDestinationIDs)
        if !completedDestinationIDs.isEmpty {
            state.shouldScrollToSelection = previousShouldScrollToSelection
        }
        if let previousLastSelectedID,
           completedDestinationIDs.contains(previousLastSelectedID)
        {
            state.lastSelectedId = previousLastSelectedID
        }
        if let previousRangeAnchorID,
           completedDestinationIDs.contains(previousRangeAnchorID)
        {
            state.rangeAnchorId = previousRangeAnchorID
        }
        guard previousSelection != state.selectedIds
            || previousLastSelectedID != state.lastSelectedId
            || previousRangeAnchorID != state.rangeAnchorId
        else { return .none }
        return .send(.delegate(.selectionChanged))
    }

    private func handleIdentityReplacementEntryOperationsAction(
        _ action: EntryOperationsFeature.Action,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .loading(.itemsLoaded(items)):
            applyIdentityReplacementEntries(items, state: &state)
        default:
            .none
        }
    }

    private func handleIdentityReplacementHierarchyAction(
        _ action: EntryListHierarchyAction,
        state: inout State,
    ) -> Effect<Action> {
        guard case let .folderChildrenResponse(_, _, _, response) = action,
              case let .event(.coreBatch(items, _)) = response
        else { return .none }
        return applyIdentityReplacementEntries(items, state: &state)
    }

    private func applyIdentityReplacementEntries(
        _ entries: [EntryModel],
        state: inout State,
    ) -> Effect<Action> {
        guard var replacement = state.identityReplacement else { return .none }
        let previousSelection = state.selectedIds
        let previousLastSelectedID = state.lastSelectedId
        let previousRangeAnchorID = state.rangeAnchorId

        for (index, pair) in replacement.plan.pairs.enumerated() {
            let afterPath = pair.afterLexicalPath.isEmpty ? pair.afterPath : pair.afterLexicalPath
            guard entries.contains(where: { standardizedPath($0.id) == standardizedPath(afterPath) }) else {
                continue
            }
            replacement.projectedPairIndexes.insert(index)

            let beforePath = pair.beforeLexicalPath.isEmpty ? pair.beforePath : pair.beforeLexicalPath
            guard let beforeID = state.selectedIds.first(where: {
                standardizedPath($0) == standardizedPath(beforePath)
            }),
                let afterID = entries.first(where: {
                    standardizedPath($0.id) == standardizedPath(afterPath)
                })?.id
            else { continue }
            state.selectedIds.remove(beforeID)
            state.selectedIds.insert(afterID)
            if state.lastSelectedId == beforeID {
                state.lastSelectedId = afterID
            }
            if state.rangeAnchorId == beforeID {
                state.rangeAnchorId = afterID
            }
        }

        state.identityReplacement = replacement
        let allProjected = replacement.projectedPairIndexes.count == replacement.plan.pairs.count
        let hasOwnedDeferredReplacement = replacement.sourceFolderIDs.contains {
            state.hierarchy.deferredFolderReplacement(folderID: $0) != nil
        }
        guard allProjected, !hasOwnedDeferredReplacement else {
            guard previousSelection != state.selectedIds
                || previousLastSelectedID != state.lastSelectedId
                || previousRangeAnchorID != state.rangeAnchorId
            else { return .none }
            return .send(.delegate(.selectionChanged))
        }

        let transactionID = replacement.plan.transactionID
        state.identityReplacement = nil
        var effects: [Effect<Action>] = [
            .send(.delegate(.identityReplacementSettled(id: transactionID, outcome: .completed))),
        ]
        if previousSelection != state.selectedIds
            || previousLastSelectedID != state.lastSelectedId
            || previousRangeAnchorID != state.rangeAnchorId
        {
            effects.insert(.send(.delegate(.selectionChanged)), at: 0)
        }
        return .merge(effects)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func canonicalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func parentPath(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
    }

    private func isSameOrDescendant(path: String, of ancestor: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let ancestorComponents = URL(fileURLWithPath: ancestor).pathComponents
        return pathComponents.starts(with: ancestorComponents)
    }
}

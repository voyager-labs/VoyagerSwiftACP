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
    private var entryLoadingClient

    public init() {}

    enum CollectionOperation: Hashable {
        case replace
        case append(Int)
    }

    public var body: some Reducer<State, Action> {
        EntryListHierarchyReducer()

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryThumbnail, action: \.entryThumbnail) {
            EntryThumbnailFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        Reduce { state, action in
            switch action {
            case let .internal(.setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                let previousSelection = state.selectedIds
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = rangeAnchorId
                state.shouldScrollToSelection = shouldScrollToSelection

                var effects: [Effect<Action>] = []
                if let renamingId = state.entryOperations.renamingItemId {
                    let isRenamingItemSelected = ids == [renamingId]
                    if !isRenamingItemSelected {
                        effects.append(.send(.entryOperations(.edit(.cancelRename))))
                    }
                }

                if previousSelection != ids {
                    effects.append(.send(.delegate(.selectionChanged)))
                }

                return .merge(effects)

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
                let previousSelection = state.selectedIds
                state.selectedIds = []
                state.lastSelectedId = nil
                state.rangeAnchorId = nil
                state.shouldScrollToSelection = false
                guard !previousSelection.isEmpty else { return .none }
                return .send(.delegate(.selectionChanged))

            case .internal(.reconcileHierarchySelection):
                Self.reconcileSelectionWithVisibleEntries(&state)
                return .none

            case let .internal(.applySelectionOffset(offset, isShiftPressed, orderedItemIds)):
                guard !orderedItemIds.isEmpty else { return .none }
                let previousSelection = state.selectedIds

                guard let currentId = state.lastSelectedId,
                      let currentIndex = orderedItemIds.firstIndex(of: currentId)
                else {
                    let fallbackItemId = offset >= 0 ? orderedItemIds.first : orderedItemIds.last
                    guard let itemId = fallbackItemId else { return .none }
                    state.selectedIds = [itemId]
                    state.lastSelectedId = itemId
                    state.rangeAnchorId = itemId
                    state.shouldScrollToSelection = true
                    guard previousSelection != state.selectedIds else { return .none }
                    return .send(.delegate(.selectionChanged))
                }

                let targetIndex: Int
                if abs(offset) > 1 {
                    let columnCount = max(1, state.gridColumnCount)
                    let currentRow = currentIndex / columnCount
                    let currentCol = currentIndex % columnCount
                    let targetRow = currentRow + (offset > 0 ? 1 : -1)
                    let totalRows = (orderedItemIds.count + columnCount - 1) / columnCount

                    guard targetRow >= 0, targetRow < totalRows else { return .none }

                    let targetRowStart = targetRow * columnCount
                    let targetRowEnd = min(orderedItemIds.count - 1, (targetRow + 1) * columnCount - 1)
                    var candidate = targetRowStart + currentCol
                    if candidate > targetRowEnd {
                        candidate = targetRowEnd
                    }
                    targetIndex = candidate
                } else {
                    targetIndex = max(0, min(orderedItemIds.count - 1, currentIndex + offset))
                }

                let targetItemId = orderedItemIds[targetIndex]
                if isShiftPressed {
                    let anchorId = state.rangeAnchorId ?? currentId
                    guard let anchorIndex = orderedItemIds.firstIndex(of: anchorId) else { return .none }
                    let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                    state.selectedIds = Set(orderedItemIds[range])
                    state.rangeAnchorId = anchorId
                } else {
                    state.selectedIds = [targetItemId]
                    state.rangeAnchorId = targetItemId
                }

                state.lastSelectedId = targetItemId
                state.shouldScrollToSelection = true
                guard previousSelection != state.selectedIds else { return .none }
                return .send(.delegate(.selectionChanged))

            case let .internal(.updateGridColumnCount(count)):
                state.gridColumnCount = max(1, count)
                return .none

            case let .internal(.setMode(mode)):
                state.mode = mode
                Self.reconcileSelectionWithVisibleEntries(&state)
                return .none

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

            case .view(.selectNextItem),
                 .view(.selectPreviousItem),
                 .view(.selectByOffset),
                 .view(.startDrag),
                 .view(.handleDrop),
                 .view(.dropItems),
                 .view(.openSelectedItem):
                return .none

            case let .internal(.setShowHiddenFiles(show)):
                return Self.setShowHiddenFiles(show, state: &state)

            case .view(.toggleShowHiddenFiles):
                return Self.setShowHiddenFiles(!state.showHiddenFiles, state: &state)

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

            case let .internal(.applyCollectionSearchPaths(paths, showHidden)):
                let cancellationEffects = state.activeCollectionAppendExpectedBatchIndices.keys.map {
                    Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
                }
                let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
                state.collectionReplaceEpoch &+= 1
                let epoch = state.collectionReplaceEpoch
                state.collectionItems = []
                state.activeCollectionReplacePaths = paths
                state.expectedCollectionReplaceBatchIndex = 0
                state.activeCollectionAppendExpectedBatchIndices = [:]
                state.activeCollectionAppendPaths = [:]
                state.finishedCollectionAppendTokens = []
                state.collectionCoreFinished = false
                state.collectionStreamCompleted = false
                state.collectionIncompleteFailure = nil
                state.removedCollectionPaths = []
                state.isCollectionContentLoading = true
                let priority = Self.collectionMetadataPriority(for: state)

                return .merge(
                    cancellationEffects + [
                        .cancel(id: replaceCancelID),
                        Self.updateEntriesAndReapply(&state),
                        .run { [entryLoadingClient, priority] send in
                            do {
                                for try await event in entryLoadingClient
                                    .materializePaths(paths, showHidden, priority)
                                {
                                    await send(.internal(.collectionReplaceEvent(epoch: epoch, event: event)))
                                }
                                await send(.internal(.collectionReplaceStreamCompleted(epoch: epoch)))
                            } catch {
                                await send(.internal(.collectionReplaceFailed(
                                    epoch: epoch,
                                    message: error.localizedDescription,
                                )))
                            }
                        }
                        .cancellable(id: replaceCancelID, cancelInFlight: true),
                    ],
                )

            case let .internal(.addCollectionPaths(paths)):
                guard state.isCollectionMode else { return .none }
                state.removedCollectionPaths.subtract(paths.map(Self.normalizedPath(_:)))
                state.nextCollectionAppendToken &+= 1
                let token = state.nextCollectionAppendToken
                let epoch = state.collectionReplaceEpoch
                let priority = Self.collectionMetadataPriority(for: state)
                let showHiddenFiles = state.showHiddenFiles
                state.activeCollectionAppendExpectedBatchIndices[token] = 0
                state.activeCollectionAppendPaths[token] = paths
                let appendCancelID = Self.collectionCancelID(for: .append(token), state: state)

                return .run { [entryLoadingClient, priority] send in
                    do {
                        for try await event in entryLoadingClient.materializePaths(
                            paths,
                            showHiddenFiles,
                            priority,
                        ) {
                            await send(.internal(.collectionAppendEvent(epoch: epoch, token: token, event: event)))
                        }
                        await send(.internal(.collectionAppendStreamCompleted(epoch: epoch, token: token)))
                    } catch {
                        await send(.internal(.collectionAppendFailed(
                            epoch: epoch,
                            token: token,
                            message: error.localizedDescription,
                        )))
                    }
                }
                .cancellable(id: appendCancelID)

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
                      let expectedBatchIndex = state.activeCollectionAppendExpectedBatchIndices[token]
                else { return .none }
                return Self.applyCollectionAppendEvent(
                    event,
                    token: token,
                    expectedBatchIndex: expectedBatchIndex,
                    state: &state,
                )

            case let .internal(.collectionAppendStreamCompleted(epoch, token)):
                guard epoch == state.collectionReplaceEpoch,
                      state.activeCollectionAppendExpectedBatchIndices.removeValue(forKey: token) != nil
                else { return .none }
                state.activeCollectionAppendPaths[token] = nil
                state.finishedCollectionAppendTokens.remove(token)
                return .none

            case let .internal(.collectionAppendFailed(epoch, token, message)):
                guard epoch == state.collectionReplaceEpoch,
                      state.activeCollectionAppendExpectedBatchIndices.removeValue(forKey: token) != nil
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

                let remainingItems = state.collectionItems.filter { item in
                    !Self.matchesAnyMutatedPath(item.fullPath, mutatedPaths: mutatedPaths)
                }
                guard remainingItems.count != state.collectionItems.count else {
                    return .none
                }

                state.collectionItems = IdentifiedArrayOf(uniqueElements: Array(remainingItems))
                return Self.updateEntriesAndReapply(&state)

            case .internal(.cancelCollectionMaterialization):
                let cancellationEffects = state.activeCollectionAppendExpectedBatchIndices.keys.map {
                    Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
                }
                let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
                state.collectionReplaceEpoch &+= 1
                state.activeCollectionReplacePaths = []
                state.expectedCollectionReplaceBatchIndex = 0
                state.activeCollectionAppendExpectedBatchIndices = [:]
                state.activeCollectionAppendPaths = [:]
                state.finishedCollectionAppendTokens = []
                state.collectionCoreFinished = false
                state.collectionStreamCompleted = false
                state.isCollectionContentLoading = false
                return .merge(cancellationEffects + [.cancel(id: replaceCancelID)])

            case .internal(.clearCollectionPresentation):
                let cancellationEffects = state.activeCollectionAppendExpectedBatchIndices.keys.map {
                    Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
                }
                let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
                state.collectionReplaceEpoch &+= 1
                state.isCollectionMode = false
                state.collectionItems = []
                state.activeCollectionReplacePaths = []
                state.activeCollectionAppendPaths = [:]
                state.isCollectionContentLoading = false
                state.expectedCollectionReplaceBatchIndex = 0
                state.activeCollectionAppendExpectedBatchIndices = [:]
                state.finishedCollectionAppendTokens = []
                state.collectionCoreFinished = false
                state.collectionStreamCompleted = false
                state.collectionIncompleteFailure = nil
                state.removedCollectionPaths = []
                return .merge(cancellationEffects + [
                    .cancel(id: replaceCancelID),
                    Self.updateEntriesAndReapply(&state),
                ])

            case .delegate:
                return .none

            case .entryThumbnail:
                return .none

            case .hierarchy:
                return .none

            case let .entryOperations(entryOperationsAction):
                switch entryOperationsAction {
                case let .delegate(.folderLoadEvent(request, event)):
                    return .send(.hierarchy(.folderChildrenResponse(
                        rootContextGeneration: request.id.rootContextGeneration,
                        folderID: request.id.folderID,
                        folderGeneration: request.folderGeneration,
                        .event(event),
                    )))

                case let .delegate(.folderLoadFinished(request)):
                    return .send(.hierarchy(.folderChildrenResponse(
                        rootContextGeneration: request.id.rootContextGeneration,
                        folderID: request.id.folderID,
                        folderGeneration: request.folderGeneration,
                        .streamCompleted,
                    )))

                case let .delegate(.folderLoadFailed(request, failure)):
                    return .send(.hierarchy(.folderChildrenResponse(
                        rootContextGeneration: request.id.rootContextGeneration,
                        folderID: request.id.folderID,
                        folderGeneration: request.folderGeneration,
                        .failed(Self.hierarchyFailure(from: failure)),
                    )))

                case .loading(.cancelAndClearItems),
                     .loading(.itemsLoaded),
                     .loading(.itemsLoadFailed),
                     .loading(.streamEvent),
                     .loading(.streamFailed):
                    return Self.updateEntriesAndReapply(&state)

                default:
                    return .none
                }

            case let .entryArrangements(entryArrangementsAction):
                switch entryArrangementsAction {
                case .setSortKey, .setSortOrder, .setGroupKey:
                    Self.reconcileSelectionWithVisibleEntries(&state)
                    return .none

                case .delegate(.requestApply):
                    return .send(.entryArrangements(.apply(
                        items: state.entries,
                        isCollectionMode: state.isCollectionMode,
                    )))

                case let .delegate(.applied(sortedItems, _)):
                    state.entries = sortedItems
                    Self.reconcileSelectionWithVisibleEntries(&state)
                    return .none

                default:
                    return .none
                }
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

    static func hierarchyFailure(from failure: EntryFolderLoadFailure) -> EntryLoadFailure {
        switch failure {
        case .permissionDenied:
            .permissionDenied
        case let .unavailable(description):
            .unavailable(description: description)
        }
    }

    static func updateEntriesAndReapply(_ state: inout State) -> Effect<Action> {
        state.entries = state.displayOrderItems
        reconcileSelectionWithVisibleEntries(&state)
        return .merge(
            .send(.entryArrangements(.reapply)),
            reconcileRenamingItemWithVisibleEntries(state),
        )
    }

    static func reconcileRenamingItemWithVisibleEntries(_ state: State) -> Effect<Action> {
        guard let renamingID = state.entryOperations.renamingItemId,
              !state.visibleSelectableEntryIDs(isNormalDirectoryPage: true).contains(renamingID)
        else { return .none }
        return .send(.entryOperations(.edit(.cancelRename)))
    }

    static func setShowHiddenFiles(_ showHiddenFiles: Bool, state: inout State) -> Effect<Action> {
        guard state.showHiddenFiles != showHiddenFiles else { return .none }
        state.showHiddenFiles = showHiddenFiles
        guard !state.hierarchy.foldersByID.isEmpty else { return .none }
        return .send(.hierarchy(.hiddenFilesSettingChanged))
    }

    static func updateEntriesPreservingOrder(_ state: inout State) {
        let currentItems = Dictionary(uniqueKeysWithValues: state.displayOrderItems.map { ($0.id, $0) })
        let existingIDs = Set(state.entries.map(\.id))
        state.entries = state.entries.compactMap { currentItems[$0.id] }
            + state.displayOrderItems.filter { !existingIDs.contains($0.id) }
        reconcileSelectionWithVisibleEntries(&state)
    }

    static func metadataPatchesAffectActiveArrangement(
        _ patches: [EntryMetadataPatch],
        state: State,
    ) -> Bool {
        let activeProbes = [
            metadataProbe(for: state.entryArrangements.sortKey),
            metadataProbe(for: state.entryArrangements.groupKey),
        ].compactMap(\.self)
        guard !activeProbes.isEmpty else { return false }
        return patches.contains { patch in
            switch patch {
            case .spotlight:
                activeProbes.contains(.spotlight)
            case .tags:
                activeProbes.contains(.tags)
            case .supplementaryMetadata:
                activeProbes.contains(.supplementaryMetadata)
            }
        }
    }

    static func metadataProbe(for key: SortKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    static func metadataProbe(for key: GroupKey) -> EntryMetadataProbe? {
        switch key {
        case .kind, .application, .dateLastOpened:
            .spotlight
        case .tags:
            .tags
        case .none, .name, .size, .dateModified, .dateCreated, .dateAdded:
            nil
        }
    }

    static func applyCollectionEvent(
        _ event: EntryLoadEvent,
        state: inout State,
        expectedBatchIndex: WritableKeyPath<State, Int>,
    ) -> Effect<Action> {
        switch event {
        case let .coreBatch(items, batchIndex):
            guard !state.collectionCoreFinished,
                  batchIndex == state[keyPath: expectedBatchIndex]
            else { return .none }
            state[keyPath: expectedBatchIndex] += 1
            appendCollectionItems(items, state: &state)
            state.isCollectionContentLoading = false
            return updateEntriesAndReapply(&state)

        case let .coreFinished(batchCount):
            guard !state.collectionCoreFinished,
                  batchCount == state[keyPath: expectedBatchIndex]
            else { return .none }
            state.collectionCoreFinished = true
            state.isCollectionContentLoading = false
            return updateEntriesAndReapply(&state)

        case let .metadataPatches(patches):
            guard state.collectionCoreFinished else { return .none }
            return applyCollectionMetadataPatches(patches, state: &state)
        }
    }

    static func applyCollectionAppendEvent(
        _ event: EntryLoadEvent,
        token: Int,
        expectedBatchIndex: Int,
        state: inout State,
    ) -> Effect<Action> {
        switch event {
        case let .coreBatch(items, batchIndex):
            guard !state.finishedCollectionAppendTokens.contains(token),
                  batchIndex == expectedBatchIndex else { return .none }
            state.activeCollectionAppendExpectedBatchIndices[token] = expectedBatchIndex + 1
            appendCollectionItems(items, state: &state)
            return updateEntriesAndReapply(&state)

        case let .coreFinished(batchCount):
            guard !state.finishedCollectionAppendTokens.contains(token),
                  batchCount == expectedBatchIndex else { return .none }
            state.finishedCollectionAppendTokens.insert(token)
            return .none

        case let .metadataPatches(patches):
            guard state.finishedCollectionAppendTokens.contains(token) else { return .none }
            return applyCollectionMetadataPatches(patches, state: &state)
        }
    }

    static func appendCollectionItems(_ items: [EntryModel], state: inout State) {
        var acceptedIDs = Set(state.collectionItems.map(\.id))
        let appendedItems = items.filter { item in
            guard !matchesAnyMutatedPath(item.fullPath, mutatedPaths: state.removedCollectionPaths),
                  acceptedIDs.insert(item.id).inserted
            else { return false }
            return true
        }
        state.collectionItems.append(contentsOf: appendedItems)
    }

    static func applyCollectionMetadataPatches(
        _ patches: [EntryMetadataPatch],
        state: inout State,
    ) -> Effect<Action> {
        var arrangementChanged = false
        var updated = false
        for patch in patches {
            guard let id = collectionItemID(for: patch),
                  let item = state.collectionItems[id: id]
            else { continue }
            let patchedItem = item.applying(patch)
            guard patchedItem != item else { continue }
            state.collectionItems[id: id] = patchedItem
            updated = true
            arrangementChanged = arrangementChanged || patchAffectsActiveArrangement(patch, state: state)
        }
        guard updated else { return .none }
        guard arrangementChanged else {
            state.entries = state.entries.map { state.collectionItems[id: $0.id] ?? $0 }
            return .none
        }
        return updateEntriesAndReapply(&state)
    }

    static func collectionItemID(for patch: EntryMetadataPatch) -> EntryModel.ID? {
        switch patch {
        case let .spotlight(id, _, _, _), let .tags(id, _), let .supplementaryMetadata(id, _): id
        }
    }

    static func patchAffectsActiveArrangement(_ patch: EntryMetadataPatch, state: State) -> Bool {
        switch patch {
        case .spotlight:
            [SortKey.kind, .application, .dateLastOpened].contains(state.entryArrangements.sortKey)
                || [GroupKey.kind, .application, .dateLastOpened].contains(state.entryArrangements.groupKey)
        case .tags:
            state.entryArrangements.sortKey == .tags || state.entryArrangements.groupKey == .tags
        case .supplementaryMetadata:
            false
        }
    }

    static func collectionMetadataPriority(for state: State) -> EntryMetadataPriority {
        var probes: [EntryMetadataProbe] = []
        if [.kind, .application, .dateLastOpened].contains(state.entryArrangements.sortKey) {
            probes.append(.spotlight)
        }
        if state.entryArrangements.sortKey == .tags {
            probes.append(.tags)
        }
        if [.kind, .application, .dateLastOpened].contains(state.entryArrangements.groupKey) {
            probes.append(.spotlight)
        }
        if state.entryArrangements.groupKey == .tags {
            probes.append(.tags)
        }
        return probes.isEmpty ? .none : .active(probes)
    }

    static func reconcileSelectionWithVisibleEntries(_ state: inout State) {
        let remainingIds = Set(state.visibleSelectableEntryIDs(
            isNormalDirectoryPage: state.selectionProjectionIsHierarchyEnabled,
        ))
        state.selectedIds = state.selectedIds.intersection(remainingIds)
        state.advanceOutlineProjectionRevision()

        guard !state.selectedIds.isEmpty else {
            state.lastSelectedId = nil
            state.rangeAnchorId = nil
            state.shouldScrollToSelection = false
            return
        }

        if state.lastSelectedId.map(state.selectedIds.contains) != true {
            let visibleIDs = state.visibleSelectableEntryIDs(
                isNormalDirectoryPage: state.selectionProjectionIsHierarchyEnabled,
            )
            state.lastSelectedId = visibleIDs.first { state.selectedIds.contains($0) }
        }
        if state.rangeAnchorId.map(state.selectedIds.contains) != true {
            state.rangeAnchorId = state.lastSelectedId
        }
        state.shouldScrollToSelection = false
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func matchesAnyMutatedPath(_ itemPath: String, mutatedPaths: Set<String>) -> Bool {
        let normalizedItemPath = normalizedPath(itemPath)
        return mutatedPaths.contains { mutatedPath in
            normalizedItemPath == mutatedPath
                || normalizedItemPath.hasPrefix(mutatedPath == "/" ? "/" : mutatedPath + "/")
        }
    }
}

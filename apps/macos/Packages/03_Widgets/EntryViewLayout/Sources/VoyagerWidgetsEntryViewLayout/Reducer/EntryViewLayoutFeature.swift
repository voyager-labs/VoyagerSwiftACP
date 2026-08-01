import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
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

        Reduce { state, action in
            switch action {
            case let .internal(.setSelectionState(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                let previousSelection = state.selectedIds
                state.selectedIds = ids
                state.lastSelectedId = lastSelectedId
                state.rangeAnchorId = rangeAnchorId
                state.shouldScrollToSelection = shouldScrollToSelection

                var effects: [Effect<Action>] = []
                if let renamingId = state.renamingItemId {
                    let isRenamingItemSelected = ids == [renamingId]
                    if !isRenamingItemSelected {
                        effects.append(.send(.delegate(.renameCommitted(itemID: renamingId, newName: ""))))
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
                state.reconcileSelectionWithVisibleEntries()
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
                state.reconcileSelectionWithVisibleEntries()
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

            case let .view(.updateSelection(ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection)):
                return .send(.internal(.setSelectionState(
                    ids: ids,
                    lastSelectedId: lastSelectedId,
                    rangeAnchorId: rangeAnchorId,
                    shouldScrollToSelection: shouldScrollToSelection,
                )))

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

            case let .view(.dropItems(sourcePaths, destinationPath, isOptionDrag)):
                return .send(.delegate(.dropItems(
                    sourcePaths: sourcePaths,
                    destinationPath: destinationPath,
                    isOptionDrag: isOptionDrag,
                )))

            case let .view(.executeCommand(command)):
                return .send(.delegate(.executeCommand(command)))

            case let .view(.openPathInNewWindow(path)):
                return .send(.delegate(.openPathInNewWindow(path)))

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
                state.entries = projection.entries
                state.isLoading = projection.isLoading
                state.sortKey = projection.sortKey
                state.sortOrder = projection.sortOrder
                state.groupKey = projection.groupKey
                state.collapsedGroups = projection.collapsedGroups
                state.presentationSections = projection.sections.isEmpty
                    ? [.ungrouped(items: projection.entries)]
                    : projection.sections
                state.openWithApplications = projection.openWithApplications
                state.renamingItemId = projection.renamingItemId
                state.renamingText = projection.renamingText
                state.clipboardCutPaths = projection.clipboardCutPaths
                state.hasClipboardItems = projection.hasClipboardItems
                state.busyEntryPaths = projection.busyEntryPaths
                state.restorableTrashPaths = projection.restorableTrashPaths
                state.trashDirectoryPath = projection.trashDirectoryPath
                state.collectionWindowID = projection.collectionWindowID
                state.collectionLoadingCancellationOwnerID = projection.collectionLoadingCancellationOwnerID
                state.reconcileSelectionWithVisibleEntries()
                return .none

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
                let explicitPaths = Set(paths.map(Self.normalizedPath(_:)))
                state.removedCollectionPaths.subtract(explicitPaths)
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
                state.clearCollectionPresentation()
                return .merge(cancellationEffects + [
                    .cancel(id: replaceCancelID),
                    Self.updateEntriesAndReapply(&state),
                ])

            case .delegate:
                return .none

            case .hierarchy:
                return .none
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
                windowID: state.collectionWindowID,
                ownerID: state.collectionLoadingCancellationOwnerID,
            )
        case let .append(token):
            EntryViewLayoutCollectionCancelID.append(
                token: token,
                windowID: state.collectionWindowID,
                ownerID: state.collectionLoadingCancellationOwnerID,
            )
        }
    }

    // MARK: - Helpers

    static func updateEntriesAndReapply(_ state: inout State) -> Effect<Action> {
        state.synchronizeEntries(state.displayOrderItems)
        return .none
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
        state.synchronizeEntries(
            state.entries.compactMap { currentItems[$0.id] }
                + state.displayOrderItems.filter { !existingIDs.contains($0.id) },
        )
    }

    static func metadataPatchesAffectActiveArrangement(
        _ patches: [EntryMetadataPatch],
        state: State,
    ) -> Bool {
        let activeProbes = [
            metadataProbe(for: state.sortKey.sharedSortKey),
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
        let sortKey = state.sortKey.sharedSortKey
        return switch patch {
        case .spotlight:
            [VoyagerShared.SortKey.kind, .application, .dateLastOpened].contains(sortKey)
                || [EntryViewLayoutGroupKey.kind, .application, .dateLastOpened].contains(state.groupKey)
        case .tags:
            sortKey == .tags || state.groupKey == .tags
        case .supplementaryMetadata:
            false
        }
    }

    static func collectionMetadataPriority(for state: State) -> EntryMetadataPriority {
        var probes: [EntryMetadataProbe] = []
        let sortKey = state.sortKey.sharedSortKey
        if [VoyagerShared.SortKey.kind, .application, .dateLastOpened].contains(sortKey) {
            probes.append(.spotlight)
        }
        if sortKey == .tags {
            probes.append(.tags)
        }
        if [EntryViewLayoutGroupKey.kind, .application, .dateLastOpened].contains(state.groupKey) {
            probes.append(.spotlight)
        }
        if state.groupKey == .tags {
            probes.append(.tags)
        }
        return probes.isEmpty ? .none : .active(probes)
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

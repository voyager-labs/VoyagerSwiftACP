import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared

extension EntryViewLayoutFeature {
    static func updateEntriesAndReapply(_ state: inout State) -> Effect<Action> {
        state.synchronizeEntries(state.displayOrderItems)
        return .none
    }

    static func setShowHiddenFiles(_ showHiddenFiles: Bool, state: inout State) -> Effect<Action> {
        guard state.showHiddenFiles != showHiddenFiles else { return .none }
        state.showHiddenFiles = showHiddenFiles
        guard !state.hierarchy.nodesByID.isEmpty else { return .none }
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
            metadataProbe(for: state.entryArrangements.sortKey),
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
            state.activeAppendExpectedBatchIndices[token] = expectedBatchIndex + 1
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
        let sortKey = state.entryArrangements.sortKey
        return switch patch {
        case .spotlight:
            [VoyagerShared.SortKey.kind, .application, .dateLastOpened].contains(sortKey)
                || [GroupKey.kind, .application, .dateLastOpened]
                .contains(state.entryArrangements.groupKey)
        case .tags:
            sortKey == .tags || state.entryArrangements.groupKey == .tags
        case .supplementaryMetadata:
            false
        }
    }

    static func collectionMetadataPriority(for state: State) -> EntryMetadataPriority {
        var probes: [EntryMetadataProbe] = []
        let sortKey = state.entryArrangements.sortKey
        if [VoyagerShared.SortKey.kind, .application, .dateLastOpened].contains(sortKey) {
            probes.append(.spotlight)
        }
        if sortKey == .tags {
            probes.append(.tags)
        }
        if [GroupKey.kind, .application, .dateLastOpened].contains(state.entryArrangements.groupKey) {
            probes.append(.spotlight)
        }
        if state.entryArrangements.groupKey == .tags {
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

extension EntryViewLayoutFeature {
    func applySelectionOffset(
        offset: Int,
        isShiftPressed: Bool,
        orderedItemIds: [EntryModel.ID],
        state: inout State,
    ) -> Effect<Action> {
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
    }

    func applyCollectionSearchPaths(
        paths: [String],
        showHidden: Bool,
        priority: EntryMetadataPriority,
        state: inout State,
    ) -> Effect<Action> {
        let cancellationEffects = state.activeAppendExpectedBatchIndices.keys.map {
            Effect<Action>.cancel(id: Self.collectionCancelID(for: .append($0), state: state))
        }
        let replaceCancelID = Self.collectionCancelID(for: .replace, state: state)
        state.collectionReplaceEpoch &+= 1
        let epoch = state.collectionReplaceEpoch
        state.collectionItems = []
        state.activeCollectionReplacePaths = paths
        state.expectedCollectionReplaceBatchIndex = 0
        state.activeAppendExpectedBatchIndices = [:]
        state.activeCollectionAppendPaths = [:]
        state.finishedCollectionAppendTokens = []
        state.collectionCoreFinished = false
        state.collectionStreamCompleted = false
        state.collectionIncompleteFailure = nil
        state.removedCollectionPaths = []
        state.isCollectionContentLoading = true
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
    }

    func addCollectionPaths(_ paths: [String], state: inout State) -> Effect<Action> {
        guard state.isCollectionMode else { return .none }
        let explicitPaths = Set(paths.map(Self.normalizedPath(_:)))
        state.removedCollectionPaths.subtract(explicitPaths)
        state.nextCollectionAppendToken &+= 1
        let token = state.nextCollectionAppendToken
        let epoch = state.collectionReplaceEpoch
        let priority = Self.collectionMetadataPriority(for: state)
        let showHiddenFiles = state.showHiddenFiles
        state.activeAppendExpectedBatchIndices[token] = 0
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
    }
}

extension EntryViewLayoutFeature {
    func setSelectionState(
        ids: Set<EntryModel.ID>,
        lastSelectedId: EntryModel.ID?,
        rangeAnchorId: EntryModel.ID?,
        shouldScrollToSelection: Bool,
        state: inout State,
    ) -> Effect<Action> {
        let previousSelection = state.selectedIds
        state.selectedIds = ids
        state.lastSelectedId = lastSelectedId
        state.rangeAnchorId = rangeAnchorId
        state.shouldScrollToSelection = shouldScrollToSelection

        var effects: [Effect<Action>] = []
        if let renamingId = state.entryOperations.renamingItemId {
            let isRenamingItemSelected = ids == [renamingId]
            if !isRenamingItemSelected {
                effects.append(.send(.delegate(.renameCanceled)))
            }
        }

        if previousSelection != ids {
            effects.append(.send(.delegate(.selectionChanged)))
        }

        return .merge(effects)
    }
}

extension EntryViewLayoutFeature {
    func applyClearSelection(state: inout State) -> Effect<Action> {
        let previousSelection = state.selectedIds
        state.selectedIds = []
        state.lastSelectedId = nil
        state.rangeAnchorId = nil
        state.shouldScrollToSelection = false
        var effects: [Effect<Action>] = []
        if let renamingId = state.entryOperations.renamingItemId,
           previousSelection.contains(renamingId)
        {
            effects.append(.send(.delegate(.renameCanceled)))
        }
        if previousSelection != state.selectedIds {
            effects.append(.send(.delegate(.selectionChanged)))
        }
        return .merge(effects)
    }
}

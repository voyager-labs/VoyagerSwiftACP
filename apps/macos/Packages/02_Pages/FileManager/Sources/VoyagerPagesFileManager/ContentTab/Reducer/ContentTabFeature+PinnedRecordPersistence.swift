import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

struct PinnedRecordPersistenceCancelID: Hashable {
    let scopeID: UUID
    let tabID: ContentTabID
}

enum PinnedRecordPersistenceIntent {
    private struct Key: Hashable {
        let scopeID: UUID
        let tabID: ContentTabID
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var latestIntentIDs: [Key: UUID] = [:]

    static func markLatest(scopeID: UUID, tabID: ContentTabID) -> UUID {
        let intentID = UUID()
        lock.lock()
        latestIntentIDs[Key(scopeID: scopeID, tabID: tabID)] = intentID
        lock.unlock()
        return intentID
    }

    static func isCurrent(scopeID: UUID, tabID: ContentTabID, intentID: UUID) -> Bool {
        lock.lock()
        let isCurrent = latestIntentIDs[Key(scopeID: scopeID, tabID: tabID)] == intentID
        lock.unlock()
        return isCurrent
    }

    /// 해당 탭의 최신 persistence intent ID를 반환한다. 테스트가 터미널 context를 구성할 때 사용한다.
    static func latestIntentID(scopeID: UUID, tabID: ContentTabID) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return latestIntentIDs[Key(scopeID: scopeID, tabID: tabID)]
    }

    static func checkCurrent(scopeID: UUID, tabID: ContentTabID, intentID: UUID) throws {
        if !isCurrent(scopeID: scopeID, tabID: tabID, intentID: intentID) {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

func upsertPinnedRecord(
    _ record: ContentTabPinnedRecord,
    in existingStore: ContentTabPinnedRecordStore,
    dormantSlot: FileManagerTopNavigationOrderPolicy.DormantContentTabSlot? = nil,
    placement: ContentTabPlacement? = nil,
    discoveredLocationIDs: [String] = [],
) -> ContentTabPinnedRecordStore {
    let tabID = ContentTabID(rawValue: record.id)
    if let placement {
        let projection = FileManagerTopNavigationOrderPolicy.normalize(
            store: existingStore,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        guard let insertedOrder = FileManagerTopNavigationOrderPolicy.insertingContentTab(
            tabID,
            at: placement,
            in: projection.durableOrder,
        ) else { return existingStore }
        var records = projection.normalizedStore.records
        if let existingIndex = records.firstIndex(where: { $0.id == record.id }) {
            records[existingIndex] = record
        } else {
            records.append(record)
        }
        return ContentTabPinnedRecordStore(
            schemaVersion: projection.normalizedStore.schemaVersion,
            records: records,
            topNavigationOrder: insertedOrder,
        )
    }

    var records = existingStore.records
    let existingIndex = records.firstIndex(where: { $0.id == record.id })
    if let existingIndex {
        records[existingIndex] = record
    } else {
        records.append(record)
    }
    let baseStore = ContentTabPinnedRecordStore(
        schemaVersion: existingStore.schemaVersion,
        records: records,
        topNavigationOrder: existingStore.topNavigationOrder,
    )
    var normalizedStore = FileManagerTopNavigationOrderPolicy.normalize(
        store: baseStore,
        discoveredLocationIDs: discoveredLocationIDs,
    ).normalizedStore
    if existingIndex == nil || dormantSlot != nil {
        normalizedStore.topNavigationOrder = FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
            tabID,
            into: normalizedStore.topNavigationOrder,
            dormantSlot: dormantSlot,
        )
    }
    return normalizedStore
}

func removePinnedRecord(
    id: String,
    from existingStore: ContentTabPinnedRecordStore,
    discoveredLocationIDs: [String] = [],
) -> ContentTabPinnedRecordStore {
    let tabID = ContentTabID(rawValue: id)
    let baseStore = ContentTabPinnedRecordStore(
        schemaVersion: existingStore.schemaVersion,
        records: existingStore.records.filter { $0.id != id },
        topNavigationOrder: .init(items: existingStore.topNavigationOrder.items.filter {
            $0 != .contentTab(tabID)
        }),
    )
    return FileManagerTopNavigationOrderPolicy.normalize(
        store: baseStore,
        discoveredLocationIDs: discoveredLocationIDs,
    ).normalizedStore
}

private extension ContentTabPinnedRecordPersistenceMutation {
    var hasExplicitPlacement: Bool {
        guard case let .upsert(_, _, placement) = self else { return false }
        return placement != nil
    }
}

func applying(
    _ mutation: ContentTabPinnedRecordPersistenceMutation,
    to store: ContentTabPinnedRecordStore,
    discoveredLocationIDs: [String],
) throws -> ContentTabPinnedRecordStore {
    switch mutation {
    case let .upsert(record, dormantSlot, placement):
        if let placement {
            let durableOrder = FileManagerTopNavigationOrderPolicy.normalize(
                store: store,
                discoveredLocationIDs: discoveredLocationIDs,
            ).durableOrder
            guard FileManagerTopNavigationOrderPolicy.insertingContentTab(
                ContentTabID(rawValue: record.id),
                at: placement,
                in: durableOrder,
            ) != nil else {
                throw ContentTabPinnedRecordPersistenceCommitError.superseded
            }
        }
        return upsertPinnedRecord(
            record,
            in: store,
            dormantSlot: dormantSlot,
            placement: placement,
            discoveredLocationIDs: discoveredLocationIDs,
        )
    case let .remove(recordID):
        return removePinnedRecord(
            id: recordID,
            from: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
    }
}

func topNavigationLoadFailure(
    _ error: ContentTabPinnedRecordStoreLoadError,
) -> FileManagerTopNavigationArrangementLoadFailure {
    switch error {
    case .corruptUnavailable:
        .corrupt
    case let .futureSchemaUnavailable(schemaVersion):
        .unsupportedSchema(schemaVersion)
    }
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

func ordinaryPinInsertionIndex(in state: ContentTabState) -> Int {
    state.tabs.firstIndex(where: { !$0.isPinned }) ?? state.tabs.endIndex
}

func pinnedRecordPersistenceAction(
    request: ContentTabPinnedRecordPersistenceRequest,
    discoveredLocationIDs: [String],
    client: ContentTabPinnedRecordClient,
    defaults: UserDefaultsClient,
    persistenceScopeID: UUID,
) async -> ContentTabAction {
    do {
        try PinnedRecordPersistenceIntent.checkCurrent(
            scopeID: persistenceScopeID,
            tabID: request.tabID,
            intentID: request.context.intentID,
        )
        let disposition = try await persistPinnedRecordMutation(
            request: request,
            discoveredLocationIDs: discoveredLocationIDs,
            client: client,
            defaults: defaults,
            persistenceScopeID: persistenceScopeID,
        )
        return pinnedRecordDispositionAction(disposition, request: request)
    } catch is CancellationError {
        return .pinnedRecordSaveNotApplied(
            tabID: request.tabID,
            context: request.context,
            reason: .cancelled,
            rollback: request.rollback,
        )
    } catch let error as ContentTabPinnedRecordStoreLoadError {
        return .pinnedRecordStoreUnavailable(
            tabID: request.tabID,
            context: request.context,
            failure: topNavigationLoadFailure(error),
            rollback: request.rollback,
        )
    } catch {
        return .pinnedRecordSaveFailed(
            tabID: request.tabID,
            context: request.context,
            rollback: request.rollback,
        )
    }
}

func pinInsertionIndex(
    for placement: ContentTabPlacement?,
    sourceID: ContentTabID,
    state: ContentTabState,
) -> Int? {
    guard let placement else { return ordinaryPinInsertionIndex(in: state) }
    switch placement {
    case let .before(anchorID):
        guard anchorID != sourceID,
              state.tabs[id: anchorID]?.isPinned == true,
              state.pinnedRecords[anchorID] != nil
        else { return nil }
        return state.tabs.filter { $0.id != sourceID }.firstIndex { $0.id == anchorID }
    case let .after(anchorID):
        guard anchorID != sourceID,
              state.tabs[id: anchorID]?.isPinned == true,
              state.pinnedRecords[anchorID] != nil,
              let anchorIndex = state.tabs.filter({ $0.id != sourceID }).firstIndex(where: { $0.id == anchorID })
        else { return nil }
        return anchorIndex + 1
    case .empty:
        guard !state.tabs.contains(where: \.isPinned), state.pinnedRecords.isEmpty else { return nil }
        return 0
    }
}

func unpinInsertionIndex(
    for placement: ContentTabPlacement?,
    sourceID: ContentTabID,
    state: ContentTabState,
) -> Int? {
    let remainingTabs = state.tabs.filter { $0.id != sourceID }
    guard let placement else { return remainingTabs.endIndex }
    switch placement {
    case let .before(anchorID):
        guard anchorID != sourceID, state.tabs[id: anchorID]?.isPinned == false else { return nil }
        return remainingTabs.firstIndex { $0.id == anchorID }
    case let .after(anchorID):
        guard anchorID != sourceID,
              state.tabs[id: anchorID]?.isPinned == false,
              let anchorIndex = remainingTabs.firstIndex(where: { $0.id == anchorID })
        else { return nil }
        return anchorIndex + 1
    case .empty:
        guard !remainingTabs.contains(where: { !$0.isPinned }) else { return nil }
        return remainingTabs.endIndex
    }
}

func pinnedRecordDispositionAction(
    _ disposition: ContentTabPinnedRecordMutationDisposition,
    request: ContentTabPinnedRecordPersistenceRequest,
) -> ContentTabAction {
    switch disposition {
    case .applied:
        .pinnedRecordSaveSucceeded(tabID: request.tabID, context: request.context)
    case .superseded:
        .pinnedRecordSaveNotApplied(
            tabID: request.tabID,
            context: request.context,
            reason: .superseded,
            rollback: request.rollback,
        )
    }
}

func persistPinnedRecordMutation(
    request: ContentTabPinnedRecordPersistenceRequest,
    discoveredLocationIDs: [String],
    client: ContentTabPinnedRecordClient,
    defaults: UserDefaultsClient,
    persistenceScopeID: UUID,
) async throws -> ContentTabPinnedRecordMutationDisposition {
    if request.mutation.hasExplicitPlacement {
        let disposition = try await client.applyPersistenceMutationCommittedGuarded(
            request.context.generation,
            defaults,
            discoveredLocationIDs: discoveredLocationIDs,
            mutation: request.mutation,
        ) {
            try PinnedRecordPersistenceIntent.checkCurrent(
                scopeID: persistenceScopeID,
                tabID: request.tabID,
                intentID: request.context.intentID,
            )
        }
        switch disposition {
        case .applied:
            return .applied
        case .superseded:
            return .superseded
        }
    }
    return try await client.updateStoreGuarded(
        request.context.generation,
        defaults,
    ) { store in
        try PinnedRecordPersistenceIntent.checkCurrent(
            scopeID: persistenceScopeID,
            tabID: request.tabID,
            intentID: request.context.intentID,
        )
        return try applying(
            request.mutation,
            to: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
    }
}

func restorePinnedRecordSnapshot(
    tabID: ContentTabID,
    previousIsPinned: Bool,
    previousPinnedRecord: ContentTabPinnedRecord?,
    previousTabIndex: Int?,
    state: inout ContentTabState,
) {
    if let previousTabIndex, let tab = state.tabs[id: tabID] {
        let selectedTabIDs = state.selectedTabIDs
        let selectionAnchorID = state.selectionAnchorID
        state.tabs.remove(id: tabID)
        state.tabs.insert(tab, at: min(previousTabIndex, state.tabs.endIndex))
        state.selectedTabIDs = selectedTabIDs
        state.selectionAnchorID = selectionAnchorID
    }
    state.tabs[id: tabID]?.isPinned = previousIsPinned
    if let previousPinnedRecord {
        state.pinnedRecords[tabID] = previousPinnedRecord
    } else {
        state.pinnedRecords.removeValue(forKey: tabID)
    }
}

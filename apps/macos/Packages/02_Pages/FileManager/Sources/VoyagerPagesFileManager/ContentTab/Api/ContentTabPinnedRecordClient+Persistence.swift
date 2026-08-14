import ComposableArchitecture
import Foundation
import VoyagerShared

extension ContentTabPinnedRecordClient {
    static func defaultUpdateStoreAndLoad(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    ) -> @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> ContentTabPinnedRecordStore {
        { defaults, transform in
            let store = try loadStore(defaults)
            let updatedStore = try transform(store)
            if updatedStore != store { try saveStore(updatedStore, defaults) }
            return updatedStore
        }
    }

    static func defaultLoadTopNavigationCommit(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (UserDefaultsClient, [String]) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
    ) -> @Sendable (UserDefaultsClient, [String]) throws -> FileManagerTopNavigationCommit {
        { defaults, locationIDs in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, locationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try writableStore(from: outcome)
            return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
        }
    }

    static func defaultMoveTopNavigationItemCommitted(
        moveTopNavigationItem: @escaping @Sendable (
            UserDefaultsClient,
            [String],
            FileManagerTopNavigationItemID,
            FileManagerTopNavigationMoveDestination,
        ) throws -> ContentTabPinnedRecordStore,
    ) -> @Sendable (
        UserDefaultsClient,
        [String],
        FileManagerTopNavigationItemID,
        FileManagerTopNavigationMoveDestination,
    ) async throws -> FileManagerTopNavigationCommit {
        { defaults, locationIDs, source, destination in
            let store = try moveTopNavigationItem(defaults, locationIDs, source, destination)
            return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
        }
    }

    static func defaultApplyPersistenceMutationCommitted(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (UserDefaultsClient, [String]) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    )
        -> @Sendable (UserDefaultsClient, [String],
                      ContentTabPinnedRecordPersistenceMutation) async throws -> ContentTabPinnedRecordPersistenceCommit
    {
        { defaults, discoveredLocationIDs, mutation in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, discoveredLocationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try writableStore(from: outcome)
            let updatedStore = try applying(mutation, to: store, discoveredLocationIDs: discoveredLocationIDs)
            if updatedStore != store {
                try saveStore(updatedStore, defaults)
            }
            return ContentTabPinnedRecordPersistenceCommit(
                store: updatedStore,
                topNavigation: .init(order: updatedStore.topNavigationOrder, revision: 0),
            )
        }
    }

    static func defaultApplyDurablePinnedBatchMutationCommitted(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (UserDefaultsClient, [String]) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    )
        -> @Sendable (UserDefaultsClient, [String],
                      ContentTabTransfer
                          .DurablePinnedBatchMutation) async throws -> ContentTabPinnedRecordPersistenceCommit
    {
        { defaults, discoveredLocationIDs, mutation in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, discoveredLocationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try writableStore(from: outcome)
            let updatedStore = try applyingDurablePinnedBatchMutation(
                mutation,
                to: store,
                discoveredLocationIDs: discoveredLocationIDs,
            )
            if updatedStore != store {
                try saveStore(updatedStore, defaults)
            }
            return ContentTabPinnedRecordPersistenceCommit(
                store: updatedStore,
                topNavigation: .init(order: updatedStore.topNavigationOrder, revision: 0),
            )
        }
    }

    static func defaultMoveTopNavigationItem(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    ) -> @Sendable (
        UserDefaultsClient,
        [String],
        FileManagerTopNavigationItemID,
        FileManagerTopNavigationMoveDestination,
    ) throws -> ContentTabPinnedRecordStore {
        { defaults, locationIDs, source, destination in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, locationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try writableStore(from: outcome)
            let projection = FileManagerTopNavigationOrderPolicy.normalize(
                store: store,
                discoveredLocationIDs: locationIDs,
            )
            let movedOrder = FileManagerTopNavigationOrderPolicy.moving(
                source,
                to: destination,
                in: projection.durableOrder,
            )
            guard movedOrder != projection.durableOrder else { return store }
            var updatedStore = projection.normalizedStore
            updatedStore.topNavigationOrder = movedOrder
            try saveStore(updatedStore, defaults)
            return updatedStore
        }
    }

    static func defaultMoveTopNavigationPinnedGroupCommitted(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    ) -> @Sendable (
        UserDefaultsClient,
        [String],
        [ContentTabID],
        FileManagerTopNavigationMoveDestination,
    ) async throws -> FileManagerTopNavigationCommit {
        { defaults, locationIDs, orderedIDs, destination in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, locationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try writableStore(from: outcome)
            let projection = FileManagerTopNavigationOrderPolicy.normalize(
                store: store,
                discoveredLocationIDs: locationIDs,
            )
            let movedOrder = FileManagerTopNavigationOrderPolicy.movingPinnedContentTabs(
                orderedIDs,
                to: destination,
                in: projection.durableOrder,
            )
            guard movedOrder != projection.durableOrder else {
                return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
            }
            var updatedStore = projection.normalizedStore
            updatedStore.topNavigationOrder = movedOrder
            try saveStore(updatedStore, defaults)
            return FileManagerTopNavigationCommit(order: movedOrder, revision: 0)
        }
    }

    static func writableStore(
        from outcome: ContentTabPinnedRecordStoreLoadOutcome,
    ) throws -> ContentTabPinnedRecordStore {
        switch outcome {
        case .missing:
            return ContentTabPinnedRecordStore()
        case let .migratedV1(store), let .migratedLegacyV2(store), let .currentV2(store):
            return store
        case .corruptUnavailable:
            throw ContentTabPinnedRecordStoreLoadError.corruptUnavailable
        case let .futureSchemaUnavailable(schemaVersion, _):
            throw ContentTabPinnedRecordStoreLoadError.futureSchemaUnavailable(schemaVersion)
        }
    }

    static func applyingDurablePinnedBatchMutation(
        _ mutation: ContentTabTransfer.DurablePinnedBatchMutation,
        to store: ContentTabPinnedRecordStore,
        discoveredLocationIDs: [String],
    ) throws -> ContentTabPinnedRecordStore {
        let projection = FileManagerTopNavigationOrderPolicy.normalize(
            store: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let removedRecordIDs = Set(mutation.recordIDsToRemove)
        let upsertedRecordsByID = Dictionary(uniqueKeysWithValues: mutation.recordsToUpsert.map { ($0.id, $0) })
        let orderedTabIDSet = Set(mutation.orderedTabIDs)
        guard orderedTabIDSet.count == mutation.orderedTabIDs.count else {
            throw ContentTabPinnedRecordPersistenceCommitError.superseded
        }

        var updatedStore = projection.normalizedStore
        updatedStore.records = projection.normalizedStore.records.filter { record in
            !removedRecordIDs.contains(record.id) && upsertedRecordsByID[record.id] == nil
        } + mutation.recordsToUpsert

        let finalRecordIDs = Set(updatedStore.records.map(\.id))
        var items = projection.durableOrder.items.filter { item in
            guard case let .contentTab(id) = item else { return true }
            return !removedRecordIDs.contains(id.rawValue) && !orderedTabIDSet.contains(id)
        }

        if let pinnedPlacement = mutation.pinnedPlacement {
            guard mutation.orderedTabIDs.allSatisfy({
                FileManagerTopNavigationItemID.isValidRawID($0.rawValue)
                    && finalRecordIDs.contains($0.rawValue)
            }) else {
                throw ContentTabPinnedRecordPersistenceCommitError.superseded
            }
            let insertionIndex = try pinnedInsertionIndex(
                for: pinnedPlacement,
                in: items,
                movingIDs: orderedTabIDSet,
            )
            items.insert(
                contentsOf: mutation.orderedTabIDs.map(FileManagerTopNavigationItemID.contentTab),
                at: insertionIndex,
            )
        }

        updatedStore.topNavigationOrder = .init(items: items)
        return FileManagerTopNavigationOrderPolicy.normalize(
            store: updatedStore,
            discoveredLocationIDs: discoveredLocationIDs,
        ).normalizedStore
    }

    static func loadStoreValue(_ userDefaultsClient: UserDefaultsClient) throws -> ContentTabPinnedRecordStore {
        let outcome = try loadStoreOutcomeValue(userDefaultsClient, discoveredLocationIDs: [])
        return try writableStore(from: outcome)
    }

    static func loadStoreOutcomeValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
    ) throws -> ContentTabPinnedRecordStoreLoadOutcome {
        guard let storedValue = userDefaultsClient.object(storageKey) else {
            return .missing
        }
        guard let data = storedValue as? Data else {
            return .corruptUnavailable(originalData: Data(), reason: .invalidPayload)
        }

        let decoder = JSONDecoder()
        let header: ContentTabPinnedRecordStoreHeader
        do {
            header = try decoder.decode(ContentTabPinnedRecordStoreHeader.self, from: data)
        } catch {
            return .corruptUnavailable(originalData: data, reason: .invalidPayload)
        }

        switch header.schemaVersion {
        case 1:
            do {
                let legacyStore = try decoder.decode(ContentTabPinnedRecordStoreV1.self, from: data)
                let locations = discoveredLocationIDs.map(FileManagerTopNavigationItemID.location)
                let contentTabs = legacyStore.records.map {
                    FileManagerTopNavigationItemID.contentTab(ContentTabID(rawValue: $0.id))
                }
                return .migratedV1(ContentTabPinnedRecordStore(
                    records: legacyStore.records,
                    topNavigationOrder: .init(items: locations + contentTabs),
                ))
            } catch {
                return .corruptUnavailable(originalData: data, reason: .invalidPayload)
            }

        case 2:
            do {
                return try .currentV2(decoder.decode(ContentTabPinnedRecordStore.self, from: data))
            } catch {
                return migratedLegacyV2Outcome(
                    data: data,
                    decoder: decoder,
                    discoveredLocationIDs: discoveredLocationIDs,
                ) ?? .corruptUnavailable(originalData: data, reason: .invalidPayload)
            }

        case let schemaVersion where schemaVersion > 2:
            return .futureSchemaUnavailable(schemaVersion: schemaVersion, originalData: data)

        default:
            return .corruptUnavailable(originalData: data, reason: .invalidPayload)
        }
    }

    private static func migratedLegacyV2Outcome(
        data: Data,
        decoder: JSONDecoder,
        discoveredLocationIDs: [String],
    ) -> ContentTabPinnedRecordStoreLoadOutcome? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["topNavigationOrder"] == nil,
            let legacyStore = try? decoder.decode(ContentTabPinnedRecordStoreV1.self, from: data)
        else { return nil }

        let locations = discoveredLocationIDs.map(FileManagerTopNavigationItemID.location)
        let contentTabs = legacyStore.records.map {
            FileManagerTopNavigationItemID.contentTab(ContentTabID(rawValue: $0.id))
        }
        return .migratedLegacyV2(ContentTabPinnedRecordStore(
            records: legacyStore.records,
            topNavigationOrder: .init(items: locations + contentTabs),
        ))
    }

    static func updateStoreGuardedValue(
        _ generation: ContentTabPinnedRecordMutationGeneration,
        _ userDefaultsClient: UserDefaultsClient,
        _ transform: @escaping @Sendable (
            ContentTabPinnedRecordStore,
        ) throws -> ContentTabPinnedRecordStore,
    ) throws -> ContentTabPinnedRecordMutationDisposition {
        storageLock.lock()
        defer { storageLock.unlock() }

        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else {
            return .superseded
        }
        let store = try loadStoreValue(userDefaultsClient)
        try Task.checkCancellation()
        let updatedStore = try transform(store)
        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else {
            return .superseded
        }
        guard updatedStore != store else { return .applied }
        let data = try JSONEncoder().encode(updatedStore)
        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else {
            return .superseded
        }
        userDefaultsClient.setObject(data, storageKey)
        return .applied
    }

    private static func pinnedInsertionIndex(
        for placement: ContentTabPlacement,
        in items: [FileManagerTopNavigationItemID],
        movingIDs: Set<ContentTabID>,
    ) throws -> Int {
        switch placement {
        case let .before(anchorID):
            guard !movingIDs.contains(anchorID),
                  let anchorIndex = items.firstIndex(of: .contentTab(anchorID))
            else {
                throw ContentTabPinnedRecordPersistenceCommitError.superseded
            }
            return anchorIndex
        case let .after(anchorID):
            guard !movingIDs.contains(anchorID),
                  let anchorIndex = items.firstIndex(of: .contentTab(anchorID))
            else {
                throw ContentTabPinnedRecordPersistenceCommitError.superseded
            }
            return anchorIndex + 1
        case .empty:
            guard !items.contains(where: {
                if case .contentTab = $0 { true } else { false }
            }) else {
                throw ContentTabPinnedRecordPersistenceCommitError.superseded
            }
            return items.endIndex
        }
    }
}

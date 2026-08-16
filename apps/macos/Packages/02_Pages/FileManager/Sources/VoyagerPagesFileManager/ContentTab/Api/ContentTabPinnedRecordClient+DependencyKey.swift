import ComposableArchitecture
import Foundation
import VoyagerShared

extension ContentTabPinnedRecordClient: DependencyKey {
    nonisolated public static var liveValue: ContentTabPinnedRecordClient {
        var client = ContentTabPinnedRecordClient(
            loadStore: { userDefaultsClient in
                try Self.loadStoreValue(userDefaultsClient)
            },
            classifyStoreLoad: { userDefaultsClient, discoveredLocationIDs in
                try Self.loadStoreOutcomeValue(
                    userDefaultsClient,
                    discoveredLocationIDs: discoveredLocationIDs,
                )
            },
            saveStore: { store, userDefaultsClient in
                let data = try JSONEncoder().encode(store)
                userDefaultsClient.setObject(data, Self.storageKey)
            },
            updateStoreAndLoad: { userDefaultsClient, transform in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                try Task.checkCancellation()
                let store = try Self.loadStoreValue(userDefaultsClient)
                try Task.checkCancellation()
                let updatedStore = try transform(store)
                try Task.checkCancellation()
                guard updatedStore != store else { return store }
                let data = try JSONEncoder().encode(updatedStore)
                try Task.checkCancellation()
                userDefaultsClient.setObject(data, Self.storageKey)
                return updatedStore
            },
            moveTopNavigationItem: { userDefaultsClient, discoveredLocationIDs, source, destination in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                try Task.checkCancellation()
                let outcome = try Self.loadStoreOutcomeValue(
                    userDefaultsClient,
                    discoveredLocationIDs: discoveredLocationIDs,
                )
                let store = try Self.writableStore(from: outcome)
                let projection = FileManagerTopNavigationOrderPolicy.normalize(
                    store: store,
                    discoveredLocationIDs: discoveredLocationIDs,
                )
                let movedOrder = FileManagerTopNavigationOrderPolicy.moving(
                    source,
                    to: destination,
                    in: projection.durableOrder,
                )
                guard movedOrder != projection.durableOrder else {
                    return store
                }
                var updatedStore = projection.normalizedStore
                updatedStore.topNavigationOrder = movedOrder
                let data = try JSONEncoder().encode(updatedStore)
                try Task.checkCancellation()
                userDefaultsClient.setObject(data, Self.storageKey)
                return updatedStore
            },
            moveTopNavigationItemCommitted: { defaults, locationIDs, source, destination in
                try Self.moveTopNavigationItemCommittedValue(
                    defaults,
                    discoveredLocationIDs: locationIDs,
                    source: source,
                    destination: destination,
                )
            },
            moveTopNavigationPinnedGroupCommitted: { defaults, locationIDs, orderedIDs, destination in
                try Self.moveTopNavigationPinnedGroupCommittedValue(
                    defaults,
                    discoveredLocationIDs: locationIDs,
                    orderedIDs: orderedIDs,
                    destination: destination,
                )
            },
            loadTopNavigationCommit: { defaults, locationIDs in
                try Self.loadTopNavigationCommitValue(
                    defaults,
                    discoveredLocationIDs: locationIDs,
                )
            },
            reserveMutationGeneration: { tabID in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                let generation = ContentTabPinnedRecordMutationGeneration(tabID: tabID)
                Self.latestMutationGenerations[tabID] = generation.value
                return generation
            },
            isCurrentMutationGeneration: { generation in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                return Self.latestMutationGenerations[generation.tabID] == generation.value
            },
            reserveTopNavigationOperationToken: {
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                let token = FileManagerTopNavigationOperationToken(value: UUID())
                Self.latestTopNavigationOperationToken = token.value
                return token
            },
            isCurrentTopNavigationOperationToken: { token in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                return Self.latestTopNavigationOperationToken == token.value
            },
            guardedUpdateStore: { generation, userDefaultsClient, transform in
                try Self.updateStoreGuardedValue(generation, userDefaultsClient, transform)
            },
            applyPersistenceMutationCommitted: { defaults, discoveredLocationIDs, mutation in
                try Self.applyPersistenceMutationCommittedValue(
                    defaults,
                    discoveredLocationIDs: discoveredLocationIDs,
                    mutation: mutation,
                )
            },
            applyDurablePinnedBatchMutationCommitted: { defaults, discoveredLocationIDs, mutation in
                try Self.applyDurablePinnedBatchMutationCommittedValue(
                    defaults,
                    discoveredLocationIDs: discoveredLocationIDs,
                    mutation: mutation,
                )
            },
        )
        client.guardedApplyPersistenceMutationCommitted = { generation, defaults, locationIDs, mutation, validate in
            try Self.applyPersistenceMutationCommittedGuardedValue(
                generation,
                defaults,
                discoveredLocationIDs: locationIDs,
                mutation: mutation,
                validateCurrentIntent: validate,
            )
        }
        return client
    }

    nonisolated public static var testValue: ContentTabPinnedRecordClient {
        ContentTabPinnedRecordClient(
            loadStore: { _ in ContentTabPinnedRecordStore() },
            saveStore: { _, _ in },
            updateStore: { _, _ in },
        )
    }

    nonisolated public static var previewValue: ContentTabPinnedRecordClient {
        testValue
    }

    nonisolated private static let storageKey = "fileManager.pinnedContentTabs.v1"
    nonisolated private static let storageLock = NSLock()
    nonisolated(unsafe) private static var latestMutationGenerations: [ContentTabID: UUID] = [:]
    nonisolated(unsafe) private static var latestTopNavigationOperationToken: UUID?
    nonisolated(unsafe) private static var latestTopNavigationCommitRevision: UInt64 = 0

    private static func applyPersistenceMutationCommittedGuardedValue(
        _ generation: ContentTabPinnedRecordMutationGeneration,
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        mutation: ContentTabPinnedRecordPersistenceMutation,
        validateCurrentIntent: @escaping @Sendable () throws -> Void,
    ) throws -> ContentTabPinnedRecordGuardedCommitDisposition {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else { return .superseded }
        try validateCurrentIntent()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        let updatedStore: ContentTabPinnedRecordStore
        do {
            updatedStore = try applying(
                mutation,
                to: store,
                discoveredLocationIDs: discoveredLocationIDs,
            )
        } catch ContentTabPinnedRecordPersistenceCommitError.superseded {
            return .superseded
        }
        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else { return .superseded }
        try validateCurrentIntent()
        guard updatedStore != store else {
            return .applied(ContentTabPinnedRecordPersistenceCommit(
                store: store,
                topNavigation: .init(order: store.topNavigationOrder, revision: latestTopNavigationCommitRevision),
            ))
        }
        let data = try JSONEncoder().encode(updatedStore)
        try Task.checkCancellation()
        guard latestMutationGenerations[generation.tabID] == generation.value else { return .superseded }
        try validateCurrentIntent()
        userDefaultsClient.setObject(data, storageKey)
        latestTopNavigationCommitRevision &+= 1
        return .applied(ContentTabPinnedRecordPersistenceCommit(
            store: updatedStore,
            topNavigation: .init(
                order: updatedStore.topNavigationOrder,
                revision: latestTopNavigationCommitRevision,
            ),
        ))
    }

    private static func applyPersistenceMutationCommittedValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        mutation: ContentTabPinnedRecordPersistenceMutation,
    ) throws -> ContentTabPinnedRecordPersistenceCommit {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        let updatedStore = try applying(
            mutation,
            to: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        try Task.checkCancellation()
        if updatedStore != store {
            let data = try JSONEncoder().encode(updatedStore)
            try Task.checkCancellation()
            userDefaultsClient.setObject(data, storageKey)
        }
        latestTopNavigationCommitRevision &+= 1
        return ContentTabPinnedRecordPersistenceCommit(
            store: updatedStore,
            topNavigation: .init(
                order: updatedStore.topNavigationOrder,
                revision: latestTopNavigationCommitRevision,
            ),
        )
    }

    private static func applyDurablePinnedBatchMutationCommittedValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        mutation: ContentTabTransfer.DurablePinnedBatchMutation,
    ) throws -> ContentTabPinnedRecordPersistenceCommit {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        let updatedStore = try applyingDurablePinnedBatchMutation(
            mutation,
            to: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        try Task.checkCancellation()
        if updatedStore != store {
            let data = try JSONEncoder().encode(updatedStore)
            try Task.checkCancellation()
            userDefaultsClient.setObject(data, storageKey)
        }
        latestTopNavigationCommitRevision &+= 1
        return ContentTabPinnedRecordPersistenceCommit(
            store: updatedStore,
            topNavigation: .init(
                order: updatedStore.topNavigationOrder,
                revision: latestTopNavigationCommitRevision,
            ),
        )
    }

    private static func loadTopNavigationCommitValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
    ) throws -> FileManagerTopNavigationCommit {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        return FileManagerTopNavigationCommit(
            order: store.topNavigationOrder,
            revision: latestTopNavigationCommitRevision,
        )
    }

    private static func moveTopNavigationItemCommittedValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        source: FileManagerTopNavigationItemID,
        destination: FileManagerTopNavigationMoveDestination,
    ) throws -> FileManagerTopNavigationCommit {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        let projection = FileManagerTopNavigationOrderPolicy.normalize(
            store: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let movedOrder = FileManagerTopNavigationOrderPolicy.moving(
            source,
            to: destination,
            in: projection.durableOrder,
        )
        let committedStore: ContentTabPinnedRecordStore
        if movedOrder == projection.durableOrder {
            committedStore = store
        } else {
            var updatedStore = projection.normalizedStore
            updatedStore.topNavigationOrder = movedOrder
            let data = try JSONEncoder().encode(updatedStore)
            try Task.checkCancellation()
            userDefaultsClient.setObject(data, storageKey)
            committedStore = updatedStore
        }
        latestTopNavigationCommitRevision &+= 1
        return FileManagerTopNavigationCommit(
            order: committedStore.topNavigationOrder,
            revision: latestTopNavigationCommitRevision,
        )
    }

    private static func moveTopNavigationPinnedGroupCommittedValue(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        orderedIDs: [ContentTabID],
        destination: FileManagerTopNavigationMoveDestination,
    ) throws -> FileManagerTopNavigationCommit {
        storageLock.lock()
        defer { storageLock.unlock() }
        try Task.checkCancellation()
        let outcome = try loadStoreOutcomeValue(
            userDefaultsClient,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let store = try writableStore(from: outcome)
        let projection = FileManagerTopNavigationOrderPolicy.normalize(
            store: store,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        let movedOrder = FileManagerTopNavigationOrderPolicy.movingPinnedContentTabs(
            orderedIDs,
            to: destination,
            in: projection.durableOrder,
        )
        let committedStore: ContentTabPinnedRecordStore
        if movedOrder == projection.durableOrder {
            committedStore = store
        } else {
            var updatedStore = projection.normalizedStore
            updatedStore.topNavigationOrder = movedOrder
            let data = try JSONEncoder().encode(updatedStore)
            try Task.checkCancellation()
            userDefaultsClient.setObject(data, storageKey)
            committedStore = updatedStore
        }
        latestTopNavigationCommitRevision &+= 1
        return FileManagerTopNavigationCommit(
            order: committedStore.topNavigationOrder,
            revision: latestTopNavigationCommitRevision,
        )
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

    private static func loadStoreValue(_ userDefaultsClient: UserDefaultsClient) throws -> ContentTabPinnedRecordStore {
        let outcome = try loadStoreOutcomeValue(userDefaultsClient, discoveredLocationIDs: [])
        return try writableStore(from: outcome)
    }

    private static func loadStoreOutcomeValue(
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

    private static func updateStoreGuardedValue(
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

private struct ContentTabPinnedRecordStoreHeader: Decodable {
    let schemaVersion: Int
}

private struct ContentTabPinnedRecordStoreV1: Decodable {
    let schemaVersion: Int
    let records: [ContentTabPinnedRecord]
}

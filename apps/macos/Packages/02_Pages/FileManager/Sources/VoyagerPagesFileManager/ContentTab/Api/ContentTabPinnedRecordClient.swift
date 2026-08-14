import ComposableArchitecture
import Foundation
import VoyagerShared

public struct ContentTabPinnedRecordMutationGeneration: Equatable, Sendable {
    public let tabID: ContentTabID
    public let value: UUID

    public init(tabID: ContentTabID, value: UUID = UUID()) {
        self.tabID = tabID
        self.value = value
    }
}

public enum ContentTabPinnedRecordMutationDisposition: Equatable, Sendable {
    case applied
    case superseded
}

public struct ContentTabPinnedRecordPersistenceCommit: Equatable, Sendable {
    public let store: ContentTabPinnedRecordStore
    public let topNavigation: FileManagerTopNavigationCommit

    public init(store: ContentTabPinnedRecordStore, topNavigation: FileManagerTopNavigationCommit) {
        self.store = store
        self.topNavigation = topNavigation
    }
}

public enum ContentTabPinnedRecordGuardedCommitDisposition: Equatable, Sendable {
    case applied(ContentTabPinnedRecordPersistenceCommit)
    case superseded
}

public enum ContentTabPinnedRecordPersistenceCommitError: Error, Equatable, Sendable {
    case superseded
}

public struct FileManagerTopNavigationCommit: Equatable, Sendable {
    public let order: FileManagerTopNavigationOrder
    public let revision: UInt64

    public init(order: FileManagerTopNavigationOrder, revision: UInt64) {
        self.order = order
        self.revision = revision
    }
}

public struct ContentTabPinnedRecordClient: Sendable {
    public var loadStore: @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore
    public var classifyStoreLoad: (@Sendable (
        UserDefaultsClient,
        [String],
    ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?
    public var saveStore: @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void
    public var updateStore: @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> Void
    public var updateStoreAndLoad: @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> ContentTabPinnedRecordStore
    public var moveTopNavigationItem: @Sendable (
        UserDefaultsClient,
        [String],
        FileManagerTopNavigationItemID,
        FileManagerTopNavigationMoveDestination,
    ) throws -> ContentTabPinnedRecordStore
    public var moveTopNavigationItemCommitted: @Sendable (
        UserDefaultsClient,
        [String],
        FileManagerTopNavigationItemID,
        FileManagerTopNavigationMoveDestination,
    ) async throws -> FileManagerTopNavigationCommit
    public var moveTopNavigationPinnedGroupCommitted: @Sendable (
        UserDefaultsClient,
        [String],
        [ContentTabID],
        FileManagerTopNavigationMoveDestination,
    ) async throws -> FileManagerTopNavigationCommit
    public var loadTopNavigationCommit: @Sendable (
        UserDefaultsClient,
        [String],
    ) throws -> FileManagerTopNavigationCommit
    public var reserveMutationGeneration: @Sendable (ContentTabID) -> ContentTabPinnedRecordMutationGeneration
    public var isCurrentMutationGeneration: @Sendable (ContentTabPinnedRecordMutationGeneration) -> Bool
    public var reserveTopNavigationOperationToken: @Sendable () -> FileManagerTopNavigationOperationToken
    public var isCurrentTopNavigationOperationToken: @Sendable (FileManagerTopNavigationOperationToken) -> Bool
    public var guardedUpdateStore: (@Sendable (
        ContentTabPinnedRecordMutationGeneration,
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) async throws -> ContentTabPinnedRecordMutationDisposition)?
    public var applyPersistenceMutationCommitted: @Sendable (
        UserDefaultsClient,
        [String],
        ContentTabPinnedRecordPersistenceMutation,
    ) async throws -> ContentTabPinnedRecordPersistenceCommit
    public var applyDurablePinnedBatchMutationCommitted: @Sendable (
        UserDefaultsClient,
        [String],
        ContentTabTransfer.DurablePinnedBatchMutation,
    ) async throws -> ContentTabPinnedRecordPersistenceCommit
    public var guardedApplyPersistenceMutationCommitted: (@Sendable (
        ContentTabPinnedRecordMutationGeneration,
        UserDefaultsClient,
        [String],
        ContentTabPinnedRecordPersistenceMutation,
        @escaping @Sendable () throws -> Void,
    ) async throws -> ContentTabPinnedRecordGuardedCommitDisposition)?

    nonisolated public init(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)? = nil,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
        updateStore: (@Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> Void)? = nil,
        updateStoreAndLoad: (@Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> ContentTabPinnedRecordStore)? = nil,
        moveTopNavigationItem: (@Sendable (
            UserDefaultsClient,
            [String],
            FileManagerTopNavigationItemID,
            FileManagerTopNavigationMoveDestination,
        ) throws -> ContentTabPinnedRecordStore)? = nil,
        moveTopNavigationItemCommitted: (@Sendable (
            UserDefaultsClient,
            [String],
            FileManagerTopNavigationItemID,
            FileManagerTopNavigationMoveDestination,
        ) async throws -> FileManagerTopNavigationCommit)? = nil,
        moveTopNavigationPinnedGroupCommitted: (@Sendable (
            UserDefaultsClient,
            [String],
            [ContentTabID],
            FileManagerTopNavigationMoveDestination,
        ) async throws -> FileManagerTopNavigationCommit)? = nil,
        loadTopNavigationCommit: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> FileManagerTopNavigationCommit)? = nil,
        reserveMutationGeneration: (@Sendable (
            ContentTabID,
        ) -> ContentTabPinnedRecordMutationGeneration)? = nil,
        isCurrentMutationGeneration: (@Sendable (
            ContentTabPinnedRecordMutationGeneration,
        ) -> Bool)? = nil,
        reserveTopNavigationOperationToken: (@Sendable () -> FileManagerTopNavigationOperationToken)? = nil,
        isCurrentTopNavigationOperationToken: (@Sendable (
            FileManagerTopNavigationOperationToken,
        ) -> Bool)? = nil,
        guardedUpdateStore: (@Sendable (
            ContentTabPinnedRecordMutationGeneration,
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) async throws -> ContentTabPinnedRecordMutationDisposition)? = nil,
        applyPersistenceMutationCommitted: (@Sendable (
            UserDefaultsClient,
            [String],
            ContentTabPinnedRecordPersistenceMutation,
        ) async throws -> ContentTabPinnedRecordPersistenceCommit)? = nil,
        applyDurablePinnedBatchMutationCommitted: (@Sendable (
            UserDefaultsClient,
            [String],
            ContentTabTransfer.DurablePinnedBatchMutation,
        ) async throws -> ContentTabPinnedRecordPersistenceCommit)? = nil,
    ) {
        let resolvedUpdateStoreAndLoad = updateStoreAndLoad
            ?? Self.defaultUpdateStoreAndLoad(loadStore: loadStore, saveStore: saveStore)

        let resolvedUpdateStore = updateStore ?? { userDefaultsClient, transform in
            _ = try resolvedUpdateStoreAndLoad(userDefaultsClient, transform)
        }

        self.loadStore = loadStore
        self.classifyStoreLoad = classifyStoreLoad
        self.saveStore = saveStore
        self.updateStoreAndLoad = resolvedUpdateStoreAndLoad
        self.updateStore = resolvedUpdateStore
        let resolvedMoveTopNavigationItem = moveTopNavigationItem ?? Self.defaultMoveTopNavigationItem(
            loadStore: loadStore,
            classifyStoreLoad: classifyStoreLoad,
            saveStore: saveStore,
        )
        self.moveTopNavigationItem = resolvedMoveTopNavigationItem
        self.moveTopNavigationItemCommitted = moveTopNavigationItemCommitted
            ?? Self.defaultMoveTopNavigationItemCommitted(moveTopNavigationItem: resolvedMoveTopNavigationItem)
        self.moveTopNavigationPinnedGroupCommitted = moveTopNavigationPinnedGroupCommitted
            ?? Self.defaultMoveTopNavigationPinnedGroupCommitted(
                loadStore: loadStore,
                classifyStoreLoad: classifyStoreLoad,
                saveStore: saveStore,
            )
        self.loadTopNavigationCommit = loadTopNavigationCommit
            ?? Self.defaultLoadTopNavigationCommit(
                loadStore: loadStore,
                classifyStoreLoad: classifyStoreLoad,
            )
        self.reserveMutationGeneration = reserveMutationGeneration ?? {
            ContentTabPinnedRecordMutationGeneration(tabID: $0)
        }
        self.isCurrentMutationGeneration = isCurrentMutationGeneration ?? { _ in true }
        self.reserveTopNavigationOperationToken = reserveTopNavigationOperationToken ?? {
            FileManagerTopNavigationOperationToken(value: UUID())
        }
        self.isCurrentTopNavigationOperationToken = isCurrentTopNavigationOperationToken ?? { _ in true }
        self.guardedUpdateStore = guardedUpdateStore
        self.applyPersistenceMutationCommitted = applyPersistenceMutationCommitted
            ?? Self.defaultApplyPersistenceMutationCommitted(
                loadStore: loadStore,
                classifyStoreLoad: classifyStoreLoad,
                saveStore: saveStore,
            )
        self.applyDurablePinnedBatchMutationCommitted = applyDurablePinnedBatchMutationCommitted
            ?? Self.defaultApplyDurablePinnedBatchMutationCommitted(
                loadStore: loadStore,
                classifyStoreLoad: classifyStoreLoad,
                saveStore: saveStore,
            )
    }

    public func loadStoreOutcome(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
    ) throws -> ContentTabPinnedRecordStoreLoadOutcome {
        if let classifyStoreLoad {
            return try classifyStoreLoad(userDefaultsClient, discoveredLocationIDs)
        }
        return try .currentV2(loadStore(userDefaultsClient))
    }

    public func updateStoreGuarded(
        _ generation: ContentTabPinnedRecordMutationGeneration,
        _ userDefaultsClient: UserDefaultsClient,
        _ transform: @escaping @Sendable (
            ContentTabPinnedRecordStore,
        ) throws -> ContentTabPinnedRecordStore,
    ) async throws -> ContentTabPinnedRecordMutationDisposition {
        if let guardedUpdateStore {
            return try await guardedUpdateStore(generation, userDefaultsClient, transform)
        }
        try updateStore(userDefaultsClient, transform)
        return .applied
    }

    public func applyPersistenceMutationCommittedGuarded(
        _ generation: ContentTabPinnedRecordMutationGeneration,
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
        mutation: ContentTabPinnedRecordPersistenceMutation,
        validateCurrentIntent: @escaping @Sendable () throws -> Void,
    ) async throws -> ContentTabPinnedRecordGuardedCommitDisposition {
        if let guardedApplyPersistenceMutationCommitted {
            return try await guardedApplyPersistenceMutationCommitted(
                generation,
                userDefaultsClient,
                discoveredLocationIDs,
                mutation,
                validateCurrentIntent,
            )
        }
        let disposition: ContentTabPinnedRecordMutationDisposition
        do {
            disposition = try await updateStoreGuarded(generation, userDefaultsClient) { store in
                try validateCurrentIntent()
                return try applying(
                    mutation,
                    to: store,
                    discoveredLocationIDs: discoveredLocationIDs,
                )
            }
        } catch ContentTabPinnedRecordPersistenceCommitError.superseded {
            return .superseded
        }
        guard disposition == .applied else { return .superseded }
        try validateCurrentIntent()
        guard isCurrentMutationGeneration(generation) else { return .superseded }
        let store = try loadStore(userDefaultsClient)
        return .applied(ContentTabPinnedRecordPersistenceCommit(
            store: store,
            topNavigation: .init(order: store.topNavigationOrder, revision: 0),
        ))
    }
}

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

    nonisolated static let storageKey = "fileManager.pinnedContentTabs.v1"
    nonisolated static let storageLock = NSLock()
    nonisolated(unsafe) static var latestMutationGenerations: [ContentTabID: UUID] = [:]
    nonisolated(unsafe) static var latestTopNavigationOperationToken: UUID?
    nonisolated(unsafe) static var latestTopNavigationCommitRevision: UInt64 = 0

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
}

struct ContentTabPinnedRecordStoreHeader: Decodable {
    let schemaVersion: Int
}

struct ContentTabPinnedRecordStoreV1: Decodable {
    let schemaVersion: Int
    let records: [ContentTabPinnedRecord]
}

public extension DependencyValues {
    nonisolated var contentTabPinnedRecordClient: ContentTabPinnedRecordClient {
        get { self[ContentTabPinnedRecordClient.self] }
        set { self[ContentTabPinnedRecordClient.self] = newValue }
    }
}

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
        let resolvedUpdateStore = updateStore
            ?? Self.defaultUpdateStore(using: resolvedUpdateStoreAndLoad)

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
            ?? Self.defaultMoveTopNavigationItemCommitted(resolvedMove: resolvedMoveTopNavigationItem)
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
        guardedApplyPersistenceMutationCommitted = nil
    }
}

private extension ContentTabPinnedRecordClient {
    private static func defaultUpdateStoreAndLoad(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    ) -> @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> ContentTabPinnedRecordStore {
        { userDefaultsClient, transform in
            let store = try loadStore(userDefaultsClient)
            let updatedStore = try transform(store)
            if updatedStore != store {
                try saveStore(updatedStore, userDefaultsClient)
            }
            return updatedStore
        }
    }

    private static func defaultUpdateStore(
        using resolvedUpdateStoreAndLoad: @escaping @Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> ContentTabPinnedRecordStore,
    ) -> @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> Void {
        { userDefaultsClient, transform in
            _ = try resolvedUpdateStoreAndLoad(userDefaultsClient, transform)
        }
    }

    private static func defaultMoveTopNavigationItemCommitted(
        resolvedMove: @escaping @Sendable (
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
            let store = try resolvedMove(defaults, locationIDs, source, destination)
            return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
        }
    }

    private static func defaultLoadTopNavigationCommit(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
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

    private static func defaultApplyPersistenceMutationCommitted(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
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
            let updatedStore = try applying(
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

    private static func defaultApplyDurablePinnedBatchMutationCommitted(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        classifyStoreLoad: (@Sendable (
            UserDefaultsClient,
            [String],
        ) throws -> ContentTabPinnedRecordStoreLoadOutcome)?,
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

    private static func defaultMoveTopNavigationItem(
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

    private static func defaultMoveTopNavigationPinnedGroupCommitted(
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
}

public extension ContentTabPinnedRecordClient {
    func loadStoreOutcome(
        _ userDefaultsClient: UserDefaultsClient,
        discoveredLocationIDs: [String],
    ) throws -> ContentTabPinnedRecordStoreLoadOutcome {
        if let classifyStoreLoad {
            return try classifyStoreLoad(userDefaultsClient, discoveredLocationIDs)
        }
        return try .currentV2(loadStore(userDefaultsClient))
    }

    func updateStoreGuarded(
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

    func applyPersistenceMutationCommittedGuarded(
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

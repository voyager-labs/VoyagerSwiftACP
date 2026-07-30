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
    ) {
        let resolvedUpdateStoreAndLoad = updateStoreAndLoad ?? { userDefaultsClient, transform in
            let store = try loadStore(userDefaultsClient)
            let updatedStore = try transform(store)
            if updatedStore != store {
                try saveStore(updatedStore, userDefaultsClient)
            }
            return updatedStore
        }

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
            ?? { defaults, locationIDs, source, destination in
                let store = try resolvedMoveTopNavigationItem(defaults, locationIDs, source, destination)
                return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
            }
        self.loadTopNavigationCommit = loadTopNavigationCommit ?? { defaults, locationIDs in
            let outcome: ContentTabPinnedRecordStoreLoadOutcome = if let classifyStoreLoad {
                try classifyStoreLoad(defaults, locationIDs)
            } else {
                try .currentV2(loadStore(defaults))
            }
            let store = try Self.writableStore(from: outcome)
            return FileManagerTopNavigationCommit(order: store.topNavigationOrder, revision: 0)
        }
        self.reserveMutationGeneration = reserveMutationGeneration ?? {
            ContentTabPinnedRecordMutationGeneration(tabID: $0)
        }
        self.isCurrentMutationGeneration = isCurrentMutationGeneration ?? { _ in true }
        self.reserveTopNavigationOperationToken = reserveTopNavigationOperationToken ?? {
            FileManagerTopNavigationOperationToken(value: UUID())
        }
        self.isCurrentTopNavigationOperationToken = isCurrentTopNavigationOperationToken ?? { _ in true }
        self.guardedUpdateStore = guardedUpdateStore
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
}

extension ContentTabPinnedRecordClient: DependencyKey {
    nonisolated public static var liveValue: ContentTabPinnedRecordClient {
        ContentTabPinnedRecordClient(
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
        )
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
        latestTopNavigationCommitRevision &+= 1
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

    private static func writableStore(
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
}

private struct ContentTabPinnedRecordStoreHeader: Decodable {
    let schemaVersion: Int
}

private struct ContentTabPinnedRecordStoreV1: Decodable {
    let schemaVersion: Int
    let records: [ContentTabPinnedRecord]
}

public extension DependencyValues {
    nonisolated var contentTabPinnedRecordClient: ContentTabPinnedRecordClient {
        get { self[ContentTabPinnedRecordClient.self] }
        set { self[ContentTabPinnedRecordClient.self] = newValue }
    }
}

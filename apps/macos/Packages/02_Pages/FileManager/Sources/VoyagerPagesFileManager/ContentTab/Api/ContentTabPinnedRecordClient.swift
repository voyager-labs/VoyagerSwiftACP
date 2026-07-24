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

public struct ContentTabPinnedRecordClient: Sendable {
    public var loadStore: @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore
    public var saveStore: @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void
    public var updateStore: @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> Void
    public var updateStoreAndLoad: @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> ContentTabPinnedRecordStore
    public var reserveMutationGeneration: @Sendable (ContentTabID) -> ContentTabPinnedRecordMutationGeneration
    public var isCurrentMutationGeneration: @Sendable (ContentTabPinnedRecordMutationGeneration) -> Bool
    public var guardedUpdateStore: (@Sendable (
        ContentTabPinnedRecordMutationGeneration,
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) async throws -> ContentTabPinnedRecordMutationDisposition)?

    nonisolated public init(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
        updateStore: (@Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> Void)? = nil,
        updateStoreAndLoad: (@Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> ContentTabPinnedRecordStore)? = nil,
        reserveMutationGeneration: (@Sendable (
            ContentTabID,
        ) -> ContentTabPinnedRecordMutationGeneration)? = nil,
        isCurrentMutationGeneration: (@Sendable (
            ContentTabPinnedRecordMutationGeneration,
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
        self.saveStore = saveStore
        self.updateStoreAndLoad = resolvedUpdateStoreAndLoad
        self.updateStore = resolvedUpdateStore
        self.reserveMutationGeneration = reserveMutationGeneration ?? {
            ContentTabPinnedRecordMutationGeneration(tabID: $0)
        }
        self.isCurrentMutationGeneration = isCurrentMutationGeneration ?? { _ in true }
        self.guardedUpdateStore = guardedUpdateStore
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

    private static func loadStoreValue(_ userDefaultsClient: UserDefaultsClient) throws -> ContentTabPinnedRecordStore {
        guard let data = userDefaultsClient.object(storageKey) as? Data else {
            return ContentTabPinnedRecordStore()
        }
        do {
            return try JSONDecoder().decode(ContentTabPinnedRecordStore.self, from: data)
        } catch {
            return ContentTabPinnedRecordStore()
        }
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

public extension DependencyValues {
    nonisolated var contentTabPinnedRecordClient: ContentTabPinnedRecordClient {
        get { self[ContentTabPinnedRecordClient.self] }
        set { self[ContentTabPinnedRecordClient.self] = newValue }
    }
}

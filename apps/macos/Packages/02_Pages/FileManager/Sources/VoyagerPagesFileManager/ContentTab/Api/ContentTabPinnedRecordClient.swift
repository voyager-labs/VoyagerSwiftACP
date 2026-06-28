import ComposableArchitecture
import Foundation
import VoyagerShared

public struct ContentTabPinnedRecordClient: Sendable {
    public var loadStore: @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore
    public var saveStore: @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void
    public var updateStore: @Sendable (
        UserDefaultsClient,
        @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
    ) throws -> Void

    nonisolated public init(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
        updateStore: (@Sendable (
            UserDefaultsClient,
            @escaping @Sendable (ContentTabPinnedRecordStore) throws -> ContentTabPinnedRecordStore,
        ) throws -> Void)? = nil,
    ) {
        self.loadStore = loadStore
        self.saveStore = saveStore
        self.updateStore = updateStore ?? { userDefaultsClient, transform in
            let store = try loadStore(userDefaultsClient)
            let updatedStore = try transform(store)
            try saveStore(updatedStore, userDefaultsClient)
        }
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
            updateStore: { userDefaultsClient, transform in
                Self.storageLock.lock()
                defer { Self.storageLock.unlock() }
                try Task.checkCancellation()
                let store = try Self.loadStoreValue(userDefaultsClient)
                try Task.checkCancellation()
                let updatedStore = try transform(store)
                try Task.checkCancellation()
                let data = try JSONEncoder().encode(updatedStore)
                userDefaultsClient.setObject(data, Self.storageKey)
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
}

public extension DependencyValues {
    nonisolated var contentTabPinnedRecordClient: ContentTabPinnedRecordClient {
        get { self[ContentTabPinnedRecordClient.self] }
        set { self[ContentTabPinnedRecordClient.self] = newValue }
    }
}

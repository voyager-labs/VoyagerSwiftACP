import ComposableArchitecture
import Foundation
import VoyagerShared

public struct ContentTabPinnedRecordClient: Sendable {
    public var loadStore: @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore
    public var saveStore: @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void

    nonisolated public init(
        loadStore: @escaping @Sendable (UserDefaultsClient) throws -> ContentTabPinnedRecordStore,
        saveStore: @escaping @Sendable (ContentTabPinnedRecordStore, UserDefaultsClient) throws -> Void,
    ) {
        self.loadStore = loadStore
        self.saveStore = saveStore
    }
}

extension ContentTabPinnedRecordClient: DependencyKey {
    nonisolated public static var liveValue: ContentTabPinnedRecordClient {
        ContentTabPinnedRecordClient(
            loadStore: { userDefaultsClient in
                guard let data = userDefaultsClient.object(Self.storageKey) as? Data else {
                    return ContentTabPinnedRecordStore()
                }
                do {
                    return try JSONDecoder().decode(ContentTabPinnedRecordStore.self, from: data)
                } catch {
                    return ContentTabPinnedRecordStore()
                }
            },
            saveStore: { store, userDefaultsClient in
                let data = try JSONEncoder().encode(store)
                userDefaultsClient.setObject(data, Self.storageKey)
            },
        )
    }

    nonisolated public static var testValue: ContentTabPinnedRecordClient {
        ContentTabPinnedRecordClient(
            loadStore: { _ in ContentTabPinnedRecordStore() },
            saveStore: { _, _ in },
        )
    }

    nonisolated public static var previewValue: ContentTabPinnedRecordClient {
        testValue
    }

    nonisolated private static let storageKey = "fileManager.pinnedContentTabs.v1"
}

public extension DependencyValues {
    nonisolated var contentTabPinnedRecordClient: ContentTabPinnedRecordClient {
        get { self[ContentTabPinnedRecordClient.self] }
        set { self[ContentTabPinnedRecordClient.self] = newValue }
    }
}

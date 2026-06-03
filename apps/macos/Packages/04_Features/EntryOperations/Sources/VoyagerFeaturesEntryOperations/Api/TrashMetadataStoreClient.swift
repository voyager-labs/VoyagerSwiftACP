import ComposableArchitecture
import Foundation

struct TrashMetadataStoreClient {
    var save: @Sendable (TrashMetadata) async -> Void
    var load: @Sendable () async -> [TrashMetadata]
    var find: @Sendable (_ trashPath: String) async -> TrashMetadata?
    var remove: @Sendable (_ trashPath: String) async -> Void
    var removeAll: @Sendable () async -> Void
}

extension TrashMetadataStoreClient: DependencyKey {
    nonisolated static var liveValue: TrashMetadataStoreClient {
        TrashMetadataStoreClient(
            save: { metadata in
                await TrashMetadataStore.shared.save(metadata)
            },
            load: {
                await TrashMetadataStore.shared.load()
            },
            find: { trashPath in
                await TrashMetadataStore.shared.find(trashPath: trashPath)
            },
            remove: { trashPath in
                await TrashMetadataStore.shared.remove(trashPath: trashPath)
            },
            removeAll: {
                await TrashMetadataStore.shared.removeAll()
            },
        )
    }

    nonisolated static var testValue: TrashMetadataStoreClient {
        // In-memory storage for testing
        final class InMemoryStorage: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [TrashMetadata] = []

            func save(_ metadata: TrashMetadata) {
                lock.lock()
                items.append(metadata)
                lock.unlock()
            }

            func load() -> [TrashMetadata] {
                lock.lock()
                defer { lock.unlock() }
                return items
            }

            func find(trashPath: String) -> TrashMetadata? {
                lock.lock()
                defer { lock.unlock() }
                return items.first { $0.trashPath == trashPath }
            }

            func remove(trashPath: String) {
                lock.lock()
                items.removeAll { $0.trashPath == trashPath }
                lock.unlock()
            }

            func removeAll() {
                lock.lock()
                items.removeAll()
                lock.unlock()
            }
        }

        let storage = InMemoryStorage()

        return TrashMetadataStoreClient(
            save: { metadata in
                storage.save(metadata)
            },
            load: {
                storage.load()
            },
            find: { trashPath in
                storage.find(trashPath: trashPath)
            },
            remove: { trashPath in
                storage.remove(trashPath: trashPath)
            },
            removeAll: {
                storage.removeAll()
            },
        )
    }

    nonisolated static var previewValue: TrashMetadataStoreClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var trashMetadataStoreClient: TrashMetadataStoreClient {
        get { self[TrashMetadataStoreClient.self] }
        set { self[TrashMetadataStoreClient.self] = newValue }
    }
}

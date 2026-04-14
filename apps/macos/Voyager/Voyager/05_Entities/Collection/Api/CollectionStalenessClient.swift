import ComposableArchitecture
import Foundation
import VoyagerShared

struct CollectionStalenessClient: Sendable {
    var record: @Sendable (_ path: String) -> CollectionStalenessRecord?
    var upsertRecord: @Sendable (_ path: String, _ record: CollectionStalenessRecord) -> Void
    var invalidateRecords: @Sendable (_ affectedPaths: [String]) -> Void
    var clearRecord: @Sendable (_ path: String) -> Void
    var registerCollection: @Sendable (_ path: String, _ relevanceRoots: [String]) -> Void
    var consumeInvalidation: @Sendable (_ path: String) -> Bool
}

extension CollectionStalenessClient: DependencyKey {
    static let liveValue: CollectionStalenessClient = live(userDefaultsClient: UserDefaultsClient.liveValue)

    nonisolated static let testValue = CollectionStalenessClient(
        record: { _ in nil },
        upsertRecord: { _, _ in },
        invalidateRecords: { _ in },
        clearRecord: { _ in },
        registerCollection: { _, _ in },
        consumeInvalidation: { _ in false },
    )
}

extension DependencyValues {
    nonisolated var collectionStalenessClient: CollectionStalenessClient {
        get { self[CollectionStalenessClient.self] }
        set { self[CollectionStalenessClient.self] = newValue }
    }
}

struct CollectionStalenessRecord: Codable, Equatable, Sendable {
    var definitionFingerprint: String
    var relevanceRoots: [String]
    var lastInvalidatedAt: Date?
}

private struct LegacyCollectionStalenessRecord: Codable, Equatable, Sendable {
    var scopes: [String]
    var isInvalidated: Bool
}

extension CollectionStalenessClient {
    static func live(userDefaultsClient: UserDefaultsClient) -> CollectionStalenessClient {
        .init(
            record: makeRecord(userDefaultsClient: userDefaultsClient),
            upsertRecord: makeUpsertRecord(userDefaultsClient: userDefaultsClient),
            invalidateRecords: makeInvalidateRecords(userDefaultsClient: userDefaultsClient),
            clearRecord: makeClearRecord(userDefaultsClient: userDefaultsClient),
            registerCollection: makeRegisterCollection(userDefaultsClient: userDefaultsClient),
            consumeInvalidation: makeConsumeInvalidation(userDefaultsClient: userDefaultsClient),
        )
    }

    private static func makeRecord(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable (String) -> CollectionStalenessRecord? {
        { path in
            loadStorage(userDefaultsClient: userDefaultsClient)[normalizePath(path)]
        }
    }

    private static func makeUpsertRecord(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable (String, CollectionStalenessRecord) -> Void {
        { path, record in
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            storage[normalizePath(path)] = normalizedRecord(record)
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private static func makeInvalidateRecords(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable ([String]) -> Void {
        { affectedPaths in
            let normalizedAffectedPaths = affectedPaths.map(normalizePath)
            guard !normalizedAffectedPaths.isEmpty else { return }

            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            let invalidatedAt = Date()

            for (path, record) in storage {
                let relevantAffectedPaths = normalizedAffectedPaths.filter {
                    !isCollectionDocumentPath($0, collectionPath: path)
                }
                let shouldInvalidate = relevantAffectedPaths.contains { affectedPath in
                    record.relevanceRoots.contains { affects(relevanceRoot: $0, affectedPath: affectedPath) }
                }
                guard shouldInvalidate else { continue }

                storage[path] = .init(
                    definitionFingerprint: record.definitionFingerprint,
                    relevanceRoots: record.relevanceRoots,
                    lastInvalidatedAt: invalidatedAt,
                )
            }

            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private static func makeClearRecord(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable (String) -> Void {
        { path in
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            storage.removeValue(forKey: normalizePath(path))
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private static func makeRegisterCollection(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable (String, [String]) -> Void {
        { path, relevanceRoots in
            let normalizedPath = normalizePath(path)
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            let existing = storage[normalizedPath]

            storage[normalizedPath] = .init(
                definitionFingerprint: existing?.definitionFingerprint ?? "",
                relevanceRoots: normalizedRoots(relevanceRoots),
                lastInvalidatedAt: existing?.lastInvalidatedAt,
            )
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private static func makeConsumeInvalidation(
        userDefaultsClient: UserDefaultsClient,
    ) -> @Sendable (String) -> Bool {
        { path in
            let normalizedPath = normalizePath(path)
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            guard let existing = storage[normalizedPath], existing.lastInvalidatedAt != nil else {
                return false
            }

            storage[normalizedPath] = .init(
                definitionFingerprint: existing.definitionFingerprint,
                relevanceRoots: existing.relevanceRoots,
                lastInvalidatedAt: nil,
            )
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
            return true
        }
    }

    private static func storageKey() -> String {
        CollectionKeys.stalenessRecords
    }

    private static func loadStorage(
        userDefaultsClient: UserDefaultsClient,
    ) -> [String: CollectionStalenessRecord] {
        guard let data = userDefaultsClient.object(storageKey()) as? Data else { return [:] }

        if let storage = try? PropertyListDecoder().decode([String: CollectionStalenessRecord].self, from: data) {
            return storage.reduce(into: [:]) { result, entry in
                result[normalizePath(entry.key)] = normalizedRecord(entry.value)
            }
        }

        guard let legacyStorage = try? JSONDecoder().decode([String: LegacyCollectionStalenessRecord].self, from: data)
        else {
            return [:]
        }

        let migratedStorage = legacyStorage.reduce(into: [:]) { result, entry in
            result[normalizePath(entry.key)] = normalizedRecord(entry.value)
        }
        saveStorage(migratedStorage, userDefaultsClient: userDefaultsClient)
        return migratedStorage
    }

    private static func saveStorage(
        _ storage: [String: CollectionStalenessRecord],
        userDefaultsClient: UserDefaultsClient,
    ) {
        let data = try? PropertyListEncoder().encode(storage)
        userDefaultsClient.setObject(data, storageKey())
    }

    private static func normalizedRecord(_ record: CollectionStalenessRecord) -> CollectionStalenessRecord {
        .init(
            definitionFingerprint: record.definitionFingerprint,
            relevanceRoots: normalizedRoots(record.relevanceRoots),
            lastInvalidatedAt: record.lastInvalidatedAt,
        )
    }

    private static func normalizedRecord(_ legacyRecord: LegacyCollectionStalenessRecord) -> CollectionStalenessRecord {
        .init(
            definitionFingerprint: "",
            relevanceRoots: normalizedRoots(legacyRecord.scopes),
            lastInvalidatedAt: legacyRecord.isInvalidated ? .distantPast : nil,
        )
    }

    private static func normalizedRoots(_ roots: [String]) -> [String] {
        Array(Set(roots.map(normalizePath).filter { !$0.isEmpty })).sorted()
    }

    private static func normalizePath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func affects(relevanceRoot: String, affectedPath: String) -> Bool {
        let normalizedRoot = normalizePath(relevanceRoot)
        let normalizedAffectedPath = normalizePath(affectedPath)
        guard !normalizedRoot.isEmpty else { return false }

        return normalizedAffectedPath == normalizedRoot
            || (normalizedRoot == "/"
                ? normalizedAffectedPath.hasPrefix("/")
                : normalizedAffectedPath.hasPrefix(normalizedRoot + "/"))
    }

    private static func isCollectionDocumentPath(_ changedPath: String, collectionPath: String) -> Bool {
        if changedPath == collectionPath {
            return true
        }

        let packagePrefix = collectionPath == "/" ? "/" : collectionPath + "/"
        return changedPath.hasPrefix(packagePrefix)
    }
}

import ComposableArchitecture
import Foundation
import VoyagerShared

public struct CollectionStalenessClient: Sendable {
    public var record: @Sendable (_ path: String) -> CollectionStalenessRecord?
    public var upsertRecord: @Sendable (_ path: String, _ record: CollectionStalenessRecord) -> Void
    public var invalidateRecords: @Sendable (_ affectedPaths: [String]) -> Void
    public var suppressPaths: @Sendable (_ paths: [String]) -> Void
    public var clearRecord: @Sendable (_ path: String) -> Void
    public var registerCollection: @Sendable (_ path: String, _ relevanceRoots: [String]) -> Void
    public var consumeInvalidation: @Sendable (_ path: String) -> Bool
}

extension CollectionStalenessClient: DependencyKey {
    public static let liveValue: CollectionStalenessClient = live(userDefaultsClient: UserDefaultsClient.liveValue)

    public nonisolated static let testValue = CollectionStalenessClient(
        record: { _ in nil },
        upsertRecord: { _, _ in },
        invalidateRecords: { _ in },
        suppressPaths: { _ in },
        clearRecord: { _ in },
        registerCollection: { _, _ in },
        consumeInvalidation: { _ in false }
    )
}

public extension DependencyValues {
    nonisolated var collectionStalenessClient: CollectionStalenessClient {
        get { self[CollectionStalenessClient.self] }
        set { self[CollectionStalenessClient.self] = newValue }
    }
}

public struct CollectionStalenessRecord: Codable, Equatable, Sendable {
    public var definitionFingerprint: String
    public var relevanceRoots: [String]
    public var lastInvalidatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case definitionFingerprint
        case relevanceRoots
        case lastInvalidatedAt
        case scopes
        case isInvalidated
    }

    public nonisolated init(
        definitionFingerprint: String,
        relevanceRoots: [String],
        lastInvalidatedAt: Date?
    ) {
        self.definitionFingerprint = definitionFingerprint
        self.relevanceRoots = relevanceRoots
        self.lastInvalidatedAt = lastInvalidatedAt
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definitionFingerprint = (try? container.decodeIfPresent(String.self, forKey: .definitionFingerprint)) ?? ""
        let roots = (try? container.decodeIfPresent([String].self, forKey: .relevanceRoots))
            ?? (try? container.decodeIfPresent([String].self, forKey: .scopes))
            ?? []
        relevanceRoots = roots
        let invalidatedAt = try? container.decodeIfPresent(Date.self, forKey: .lastInvalidatedAt)
        let legacyInvalidated = (try? container.decodeIfPresent(Bool.self, forKey: .isInvalidated)) ?? false
        lastInvalidatedAt = invalidatedAt ?? (legacyInvalidated ? .distantPast : nil)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definitionFingerprint, forKey: .definitionFingerprint)
        try container.encode(relevanceRoots, forKey: .relevanceRoots)
        try container.encodeIfPresent(lastInvalidatedAt, forKey: .lastInvalidatedAt)
    }
}

private struct LegacyCollectionStalenessRecord: Codable, Equatable, Sendable {
    var scopes: [String]
    var isInvalidated: Bool
}

private final class CollectionStalenessSuppressionStore: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var suppressedPaths: [String: Int] = [:]

    nonisolated func insert(_ paths: [String], count: Int = 3) {
        lock.lock()
        defer { lock.unlock() }
        for path in paths {
            suppressedPaths[path] = max(suppressedPaths[path] ?? 0, count)
        }
    }

    nonisolated func consumeIfSuppressed(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let remaining = suppressedPaths[path], remaining > 0 else {
            return false
        }
        if remaining == 1 {
            suppressedPaths.removeValue(forKey: path)
        } else {
            suppressedPaths[path] = remaining - 1
        }
        return true
    }
}

public extension CollectionStalenessClient {
    nonisolated static func live(userDefaultsClient: UserDefaultsClient) -> CollectionStalenessClient {
        let suppressionStore = CollectionStalenessSuppressionStore()
        return .init(
            record: makeRecord(userDefaultsClient: userDefaultsClient),
            upsertRecord: makeUpsertRecord(userDefaultsClient: userDefaultsClient),
            invalidateRecords: makeInvalidateRecords(
                userDefaultsClient: userDefaultsClient,
                suppressionStore: suppressionStore
            ),
            suppressPaths: makeSuppressPaths(suppressionStore: suppressionStore),
            clearRecord: makeClearRecord(userDefaultsClient: userDefaultsClient),
            registerCollection: makeRegisterCollection(userDefaultsClient: userDefaultsClient),
            consumeInvalidation: makeConsumeInvalidation(userDefaultsClient: userDefaultsClient)
        )
    }

    private nonisolated static func makeRecord(
        userDefaultsClient: UserDefaultsClient
    ) -> @Sendable (String) -> CollectionStalenessRecord? {
        { path in
            loadStorage(userDefaultsClient: userDefaultsClient)[normalizePath(path)]
        }
    }

    private nonisolated static func makeUpsertRecord(
        userDefaultsClient: UserDefaultsClient
    ) -> @Sendable (String, CollectionStalenessRecord) -> Void {
        { path, record in
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            storage[normalizePath(path)] = normalizedRecord(record)
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private nonisolated static func makeInvalidateRecords(
        userDefaultsClient: UserDefaultsClient,
        suppressionStore: CollectionStalenessSuppressionStore
    ) -> @Sendable ([String]) -> Void {
        { affectedPaths in
            let normalizedAffectedPaths = affectedPaths.map(normalizePath).filter {
                !suppressionStore.consumeIfSuppressed($0)
            }
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
                    lastInvalidatedAt: invalidatedAt
                )
            }

            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private nonisolated static func makeSuppressPaths(
        suppressionStore: CollectionStalenessSuppressionStore
    ) -> @Sendable ([String]) -> Void {
        { paths in
            suppressionStore.insert(paths.map(normalizePath))
        }
    }

    private nonisolated static func makeClearRecord(
        userDefaultsClient: UserDefaultsClient
    ) -> @Sendable (String) -> Void {
        { path in
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            storage.removeValue(forKey: normalizePath(path))
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private nonisolated static func makeRegisterCollection(
        userDefaultsClient: UserDefaultsClient
    ) -> @Sendable (String, [String]) -> Void {
        { path, relevanceRoots in
            let normalizedPath = normalizePath(path)
            var storage = loadStorage(userDefaultsClient: userDefaultsClient)
            let existing = storage[normalizedPath]

            storage[normalizedPath] = .init(
                definitionFingerprint: existing?.definitionFingerprint ?? "",
                relevanceRoots: normalizedRoots(relevanceRoots),
                lastInvalidatedAt: nil
            )
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
        }
    }

    private nonisolated static func makeConsumeInvalidation(
        userDefaultsClient: UserDefaultsClient
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
                lastInvalidatedAt: nil
            )
            saveStorage(storage, userDefaultsClient: userDefaultsClient)
            return true
        }
    }

    private nonisolated static func storageKey() -> String {
        CollectionKeys.stalenessRecords
    }

    private nonisolated static func loadStorage(
        userDefaultsClient: UserDefaultsClient
    ) -> [String: CollectionStalenessRecord] {
        guard let data = userDefaultsClient.object(storageKey()) as? Data else { return [:] }

        if let currentPlistStorage = decodeCurrentPlistStorage(data) {
            return currentPlistStorage
        }

        if let legacyPlistStorage = decodeLegacyPlistStorage(data) {
            saveStorage(legacyPlistStorage, userDefaultsClient: userDefaultsClient)
            return legacyPlistStorage
        }

        if let legacyJSONStorage = try? JSONDecoder().decode(
            [String: LegacyCollectionStalenessRecord].self,
            from: data
        ) {
            let migratedStorage = legacyJSONStorage
                .reduce(into: [String: CollectionStalenessRecord]()) { result, entry in
                    let record = normalizedRecord(entry.value)
                    guard isMeaningful(record) else { return }
                    result[normalizePath(entry.key)] = record
                }
            saveStorage(migratedStorage, userDefaultsClient: userDefaultsClient)
            return migratedStorage
        }

        return [:]
    }

    private nonisolated static func saveStorage(
        _ storage: [String: CollectionStalenessRecord],
        userDefaultsClient: UserDefaultsClient
    ) {
        let data = try? PropertyListEncoder().encode(storage)
        userDefaultsClient.setObject(data, storageKey())
    }

    private nonisolated static func normalizedRecord(_ record: CollectionStalenessRecord) -> CollectionStalenessRecord {
        .init(
            definitionFingerprint: record.definitionFingerprint,
            relevanceRoots: normalizedRoots(record.relevanceRoots),
            lastInvalidatedAt: record.lastInvalidatedAt
        )
    }

    private nonisolated static func normalizedRecord(_ legacyRecord: LegacyCollectionStalenessRecord)
        -> CollectionStalenessRecord
    {
        .init(
            definitionFingerprint: "",
            relevanceRoots: normalizedRoots(legacyRecord.scopes),
            lastInvalidatedAt: legacyRecord.isInvalidated ? .distantPast : nil
        )
    }

    private nonisolated static func normalizedRoots(_ roots: [String]) -> [String] {
        Array(Set(roots.map(normalizePath).filter { !$0.isEmpty })).sorted()
    }

    private nonisolated static func decodeCurrentPlistStorage(_ data: Data) -> [String: CollectionStalenessRecord]? {
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let topLevelAny = propertyList as? [AnyHashable: Any]
        else {
            return nil
        }
        let topLevel = topLevelAny.reduce(into: [String: Any]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = entry.value
        }

        var result: [String: CollectionStalenessRecord] = [:]
        for (path, rawRecord) in topLevel {
            guard let record = decodeRecord(from: rawRecord) else { continue }
            result[normalizePath(path)] = record
        }
        return result
    }

    private nonisolated static func decodeLegacyPlistStorage(_ data: Data) -> [String: CollectionStalenessRecord]? {
        guard let legacyStorage = try? PropertyListDecoder().decode(
            [String: LegacyCollectionStalenessRecord].self,
            from: data
        ) else {
            return nil
        }

        return legacyStorage.reduce(into: [String: CollectionStalenessRecord]()) { result, entry in
            let record = normalizedRecord(entry.value)
            guard isMeaningful(record) else { return }
            result[normalizePath(entry.key)] = record
        }
    }

    private nonisolated static func decodeRecord(from rawRecord: Any) -> CollectionStalenessRecord? {
        guard let dictionary = rawRecord as? [String: Any] else { return nil }

        let definitionFingerprint = dictionary["definitionFingerprint"] as? String ?? ""
        let relevanceRoots = normalizedRoots(
            (dictionary["relevanceRoots"] as? [String])
                ?? (dictionary["scopes"] as? [String])
                ?? []
        )

        let invalidatedAt = dictionary["lastInvalidatedAt"] as? Date
        let legacyInvalidated = dictionary["isInvalidated"] as? Bool ?? false
        let record = CollectionStalenessRecord(
            definitionFingerprint: definitionFingerprint,
            relevanceRoots: relevanceRoots,
            lastInvalidatedAt: invalidatedAt ?? (legacyInvalidated ? .distantPast : nil)
        )

        return isMeaningful(record) ? record : nil
    }

    private nonisolated static func isMeaningful(_ record: CollectionStalenessRecord) -> Bool {
        !record.definitionFingerprint.isEmpty || !record.relevanceRoots.isEmpty || record.lastInvalidatedAt != nil
    }

    private nonisolated static func normalizePath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private nonisolated static func affects(relevanceRoot: String, affectedPath: String) -> Bool {
        let normalizedRoot = normalizePath(relevanceRoot)
        let normalizedAffectedPath = normalizePath(affectedPath)
        guard !normalizedRoot.isEmpty else { return false }

        return normalizedAffectedPath == normalizedRoot
            || (normalizedRoot == "/"
                ? normalizedAffectedPath.hasPrefix("/")
                : normalizedAffectedPath.hasPrefix(normalizedRoot + "/"))
    }

    private nonisolated static func isCollectionDocumentPath(_ changedPath: String, collectionPath: String) -> Bool {
        if changedPath == collectionPath {
            return true
        }

        let packagePrefix = collectionPath == "/" ? "/" : collectionPath + "/"
        return changedPath.hasPrefix(packagePrefix)
    }
}

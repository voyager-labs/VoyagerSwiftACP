import ComposableArchitecture
import Foundation
import VoyagerShared

public struct CollectionStalenessClient: Sendable {
    public var registerCollection: @Sendable (String, [String]) -> Void
    public var invalidateRecords: @Sendable ([String]) -> Void
    public var consumeInvalidation: @Sendable (String) -> Bool
}

extension CollectionStalenessClient: DependencyKey {
    public nonisolated static let liveValue = CollectionStalenessClient(
        registerCollection: { collectionPath, scopes in
            let userDefaultsClient = UserDefaultsClient.liveValue
            var records = loadRecords(userDefaultsClient: userDefaultsClient)
            let normalizedPath = normalizePath(collectionPath)
            let normalizedScopes = scopes.map(normalizePath).filter { !$0.isEmpty }

            records[normalizedPath] = .init(
                scopes: Array(Set(normalizedScopes)).sorted(),
                isInvalidated: records[normalizedPath]?.isInvalidated ?? false,
            )
            saveRecords(records, userDefaultsClient: userDefaultsClient)
        },
        invalidateRecords: { changedPaths in
            let userDefaultsClient = UserDefaultsClient.liveValue
            var records = loadRecords(userDefaultsClient: userDefaultsClient)
            let normalizedChangedPaths = changedPaths.map(normalizePath)

            for (collectionPath, record) in records {
                let relevantChangedPaths = normalizedChangedPaths.filter {
                    !isCollectionDocumentPath($0, collectionPath: collectionPath)
                }
                let isRelevant = collectionChangeIsRelevant(changedPaths: relevantChangedPaths, scopes: record.scopes)

                if isRelevant {
                    records[collectionPath] = .init(scopes: record.scopes, isInvalidated: true)
                }
            }

            saveRecords(records, userDefaultsClient: userDefaultsClient)
        },
        consumeInvalidation: { collectionPath in
            let userDefaultsClient = UserDefaultsClient.liveValue
            var records = loadRecords(userDefaultsClient: userDefaultsClient)
            let normalizedPath = normalizePath(collectionPath)
            guard let record = records[normalizedPath], record.isInvalidated else {
                return false
            }
            records[normalizedPath] = .init(scopes: record.scopes, isInvalidated: false)
            saveRecords(records, userDefaultsClient: userDefaultsClient)
            return true
        },
    )

    public nonisolated static let testValue = CollectionStalenessClient(
        registerCollection: { _, _ in },
        invalidateRecords: { _ in },
        consumeInvalidation: { _ in false },
    )
}

public extension DependencyValues {
    nonisolated var collectionStalenessClient: CollectionStalenessClient {
        get { self[CollectionStalenessClient.self] }
        set { self[CollectionStalenessClient.self] = newValue }
    }
}

private struct CollectionStalenessRecord: Codable, Equatable {
    var scopes: [String]
    var isInvalidated: Bool
}

private nonisolated func loadRecords(userDefaultsClient: UserDefaultsClient) -> [String: CollectionStalenessRecord] {
    guard let data = userDefaultsClient.object("collectionStalenessRecords") as? Data else {
        return [:]
    }
    return (try? JSONDecoder().decode([String: CollectionStalenessRecord].self, from: data)) ?? [:]
}

private nonisolated func saveRecords(
    _ records: [String: CollectionStalenessRecord],
    userDefaultsClient: UserDefaultsClient,
) {
    let data = try? JSONEncoder().encode(records)
    userDefaultsClient.setObject(data, "collectionStalenessRecords")
}

private nonisolated func normalizePath(_ path: String) -> String {
    guard !path.isEmpty else { return path }
    return URL(fileURLWithPath: path).standardizedFileURL.path
}

private nonisolated func isCollectionDocumentPath(_ changedPath: String, collectionPath: String) -> Bool {
    if changedPath == collectionPath {
        return true
    }

    let packagePrefix = collectionPath == "/" ? "/" : collectionPath + "/"
    return changedPath.hasPrefix(packagePrefix)
}

import ComposableArchitecture
import Foundation

public struct CollectionFileClient: Sendable {
    public var save: @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void
    public var load: @Sendable (_ url: URL) async throws -> VoyagerCollectionFile

    public init(
        save: @escaping @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void,
        load: @escaping @Sendable (_ url: URL) async throws -> VoyagerCollectionFile,
    ) {
        self.save = save
        self.load = load
    }
}

extension CollectionFileClient: DependencyKey {
    public static let liveValue: CollectionFileClient = .init(
        save: { _, _ in },
        load: { _ in
            VoyagerCollectionFile(
                schemaVersion: 0,
                id: "",
                name: "",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                query: "",
                scopes: [],
                conditions: [],
                appVersion: nil,
            )
        },
    )

    public nonisolated(unsafe) static var testValue: CollectionFileClient = .init(
        save: { _, _ in },
        load: { _ in
            VoyagerCollectionFile(
                schemaVersion: 0,
                id: "",
                name: "",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                query: "",
                scopes: [],
                conditions: [],
                appVersion: nil,
            )
        },
    )
}

extension CollectionFileClient: TestDependencyKey {}

public extension DependencyValues {
    var collectionFileClient: CollectionFileClient {
        get { self[CollectionFileClient.self] }
        set { self[CollectionFileClient.self] = newValue }
    }
}

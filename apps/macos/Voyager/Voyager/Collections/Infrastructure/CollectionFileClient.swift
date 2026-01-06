import ComposableArchitecture
import Foundation

struct CollectionFileClient: Sendable {
    var save: @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void
    var load: @Sendable (_ url: URL) async throws -> VoyagerCollectionFile
}

extension CollectionFileClient: DependencyKey {
    static let liveValue: CollectionFileClient = .init(
        save: { file, url in
            let data = try await MainActor.run {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                return try encoder.encode(file)
            }
            try data.write(to: url, options: [.atomic])
        },
        load: { url in
            let data = try Data(contentsOf: url)
            return try await MainActor.run {
                let decoder = PropertyListDecoder()
                return try decoder.decode(VoyagerCollectionFile.self, from: data)
            }
        },
    )

    nonisolated(unsafe) static var testValue: CollectionFileClient = .init(
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
                sortKey: nil,
                sortOrder: nil,
                viewLayout: nil,
                appVersion: nil,
            )
        },
    )
}

extension DependencyValues {
    nonisolated var collectionFileClient: CollectionFileClient {
        get { self[CollectionFileClient.self] }
        set { self[CollectionFileClient.self] = newValue }
    }
}

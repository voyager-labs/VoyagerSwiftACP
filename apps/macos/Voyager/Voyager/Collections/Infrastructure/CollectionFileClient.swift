import ComposableArchitecture
import Foundation

struct CollectionFileClient: Sendable {
    var save: @Sendable (_ file: VoyagerCollectionFile, _ url: URL) async throws -> Void
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
    )

    nonisolated(unsafe) static var testValue: CollectionFileClient = .init(save: { _, _ in })
}

extension DependencyValues {
    nonisolated var collectionFileClient: CollectionFileClient {
        get { self[CollectionFileClient.self] }
        set { self[CollectionFileClient.self] = newValue }
    }
}

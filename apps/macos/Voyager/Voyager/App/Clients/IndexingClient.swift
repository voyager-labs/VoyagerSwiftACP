import ComposableArchitecture
import Foundation
import Logging

struct IndexingClient: Sendable {
    var start: @Sendable () async -> Void

    nonisolated init(start: @escaping @Sendable () async -> Void) {
        self.start = start
    }
}

extension IndexingClient: DependencyKey {
    nonisolated static var liveValue: IndexingClient {
        let logger = Logger(label: "Voyager")
        return IndexingClient(start: {
            logger.info("IndexingClient.start invoked.")
            await MainActor.run {
                DistributedNotificationCenter.default().post(
                    name: .voyagerIndexingRequest,
                    object: nil,
                    userInfo: nil,
                )
            }
            logger.info("Indexing request sent.")
        })
    }

    nonisolated static var testValue: IndexingClient {
        IndexingClient(start: {})
    }

    nonisolated static var previewValue: IndexingClient {
        IndexingClient(start: {})
    }
}

extension DependencyValues {
    nonisolated var indexingClient: IndexingClient {
        get { self[IndexingClient.self] }
        set { self[IndexingClient.self] = newValue }
    }
}

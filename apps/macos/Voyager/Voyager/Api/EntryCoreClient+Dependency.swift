import ComposableArchitecture
import VoyagerEntryCoreClient

nonisolated extension EntryCoreClient: @retroactive DependencyKey {
    nonisolated public static var liveValue: EntryCoreClient {
        .live
    }

    nonisolated public static var testValue: EntryCoreClient {
        EntryCoreClient(
            ping: { _ in throw EntryCoreClientError.daemonUnavailable },
            health: { _ in throw EntryCoreClientError.daemonUnavailable },
            version: { _ in throw EntryCoreClientError.daemonUnavailable },
        )
    }
}

extension DependencyValues {
    nonisolated var entryCoreClient: EntryCoreClient {
        get { self[EntryCoreClient.self] }
        set { self[EntryCoreClient.self] = newValue }
    }
}

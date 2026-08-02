import ComposableArchitecture
import Foundation
import VoyagerEntryCoreClient

nonisolated struct EntryCoreEndpointClient {
    static let environmentKey = "VOYAGER_ENTRY_CORE_SOCKET_PATH"

    var resolve: @Sendable () throws -> EntryCoreEndpoint

    nonisolated static func live(
        environment: @escaping @Sendable () -> [String: String],
    ) -> EntryCoreEndpointClient {
        EntryCoreEndpointClient {
            guard
                let path = environment()[environmentKey],
                !path.isEmpty,
                let endpoint = try? EntryCoreEndpoint(path: path)
            else {
                throw EntryCoreEndpointResolutionError.unavailable
            }
            return endpoint
        }
    }
}

nonisolated enum EntryCoreEndpointResolutionError: Error, Equatable {
    case unavailable
}

nonisolated extension EntryCoreEndpointClient: DependencyKey {
    nonisolated static var liveValue: EntryCoreEndpointClient {
        .live(environment: { ProcessInfo.processInfo.environment })
    }

    nonisolated static var testValue: EntryCoreEndpointClient {
        .live(environment: { [:] })
    }
}

extension DependencyValues {
    nonisolated var entryCoreEndpointClient: EntryCoreEndpointClient {
        get { self[EntryCoreEndpointClient.self] }
        set { self[EntryCoreEndpointClient.self] = newValue }
    }
}

import Foundation

nonisolated public struct EntryCoreClient: Sendable {
    public let ping: @Sendable (EntryCoreEndpoint) async throws -> EntryCorePingResult
    public let health: @Sendable (EntryCoreEndpoint) async throws -> EntryCoreHealthResult
    public let version: @Sendable (EntryCoreEndpoint) async throws -> EntryCoreVersionResult

    public init(
        ping: @escaping @Sendable (EntryCoreEndpoint) async throws -> EntryCorePingResult,
        health: @escaping @Sendable (EntryCoreEndpoint) async throws -> EntryCoreHealthResult,
        version: @escaping @Sendable (EntryCoreEndpoint) async throws -> EntryCoreVersionResult,
    ) {
        self.ping = ping
        self.health = health
        self.version = version
    }
}

public extension EntryCoreClient {
    nonisolated static var live: EntryCoreClient {
        makeLive(
            requestID: { UUID().uuidString },
            makeTransport: {
                { request, endpoint in
                    try await UnixSocketTransport().request(request, to: endpoint)
                }
            },
        )
    }
}

typealias EntryCoreTransportRequest = @Sendable (Data, EntryCoreEndpoint) async throws -> Data

extension EntryCoreClient {
    nonisolated static func makeLive(
        requestID: @escaping @Sendable () -> String,
        makeTransport: @escaping @Sendable () -> EntryCoreTransportRequest,
    ) -> EntryCoreClient {
        EntryCoreClient(
            ping: { endpoint in
                let response = try await call(
                    .ping,
                    endpoint: endpoint,
                    requestID: requestID,
                    makeTransport: makeTransport,
                )
                guard case let .ping(result) = response else {
                    throw EntryCoreClientError.protocolMismatch
                }
                return result
            },
            health: { endpoint in
                let response = try await call(
                    .health,
                    endpoint: endpoint,
                    requestID: requestID,
                    makeTransport: makeTransport,
                )
                guard case let .health(result) = response else {
                    throw EntryCoreClientError.protocolMismatch
                }
                return result
            },
            version: { endpoint in
                let response = try await call(
                    .version,
                    endpoint: endpoint,
                    requestID: requestID,
                    makeTransport: makeTransport,
                )
                guard case let .version(result) = response else {
                    throw EntryCoreClientError.protocolMismatch
                }
                return result
            },
        )
    }
}

private extension EntryCoreClient {
    nonisolated static func call(
        _ method: EntryCoreMethod,
        endpoint: EntryCoreEndpoint,
        requestID: @Sendable () -> String,
        makeTransport: @Sendable () -> EntryCoreTransportRequest,
    ) async throws -> EntryCoreDecodedResponse {
        let activeRequestID = requestID()
        guard
            !activeRequestID.isEmpty,
            activeRequestID.utf8.count <= 128
        else {
            throw EntryCoreClientError.protocolMismatch
        }

        let request = try encodeRequest(id: activeRequestID, method: method)
        let response = try await makeTransport()(request, endpoint)
        return try EntryCoreResponseDecoder.decode(
            Array(response),
            method: method,
            expectedRequestID: activeRequestID,
        )
    }

    nonisolated static func encodeRequest(id: String, method: EntryCoreMethod) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(EntryCoreRequestWire(
                requestID: id,
                method: method.rawValue,
                params: EntryCoreEmptyParams(),
            ))
        } catch {
            throw EntryCoreClientError.protocolMismatch
        }
    }
}

private struct EntryCoreRequestWire: Encodable {
    let requestID: String
    let method: String
    let params: EntryCoreEmptyParams

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case method
        case params
    }
}

private struct EntryCoreEmptyParams: Encodable {}

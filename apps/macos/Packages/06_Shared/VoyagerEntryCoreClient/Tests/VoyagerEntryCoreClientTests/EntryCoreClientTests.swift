import Foundation
import os
@testable import VoyagerEntryCoreClient
import XCTest

final class EntryCoreClientTests: XCTestCase {
    private let endpointPath = "/tmp/voyager-entry-core-client.sock"

    func testPingHealthAndVersionBuildExactRequestsAndReturnTypedResults() async throws {
        let requestIDs = LockedRequestIDs(["ping-id", "health-id", "version-id"])
        let factory = RecordingTransportFactory(outcomes: [
            .success(response(id: "ping-id", result: #"{"message":"pong"}"#)),
            .success(response(id: "health-id", result: #"{"status":"healthy","state":"running"}"#)),
            .success(response(id: "version-id", result: #"{"app_version":"2026.7.31","protocol_version":1}"#)),
        ])
        let client = makeClient(requestIDs: requestIDs, factory: factory)
        let endpoint = try EntryCoreEndpoint(path: endpointPath)

        let ping = try await client.ping(endpoint)
        let health = try await client.health(endpoint)
        let version = try await client.version(endpoint)

        XCTAssertEqual(ping, EntryCorePingResult())
        XCTAssertEqual(health, EntryCoreHealthResult())
        XCTAssertEqual(version, try EntryCoreVersionResult(appVersion: "2026.7.31"))
        XCTAssertEqual(factory.creationCount, 3)
        XCTAssertEqual(factory.requestCount, 3)
        try assertRequest(factory.requests[0], id: "ping-id", method: .ping)
        try assertRequest(factory.requests[1], id: "health-id", method: .health)
        try assertRequest(factory.requests[2], id: "version-id", method: .version)
        XCTAssertEqual(factory.endpoints, [endpoint, endpoint, endpoint])
    }

    func testEveryExplicitCallUsesFreshValidUUIDAndFreshTransport() async throws {
        let factory = RecordingTransportFactory(outcomes: Array(
            repeating: .failure(.daemonUnavailable),
            count: 3,
        ))
        let client = EntryCoreClient.makeLive(
            requestID: { UUID().uuidString },
            makeTransport: factory.makeTransport,
        )
        let endpoint = try EntryCoreEndpoint(path: endpointPath)

        for _ in 0 ..< 3 {
            await assertError(.daemonUnavailable) {
                try await client.ping(endpoint)
            }
        }

        let ids = factory.requests.compactMap(requestID)
        XCTAssertEqual(factory.creationCount, 3)
        XCTAssertEqual(factory.requestCount, 3)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertTrue(ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 })
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil })
    }

    func testFailureDoesNotReplayAndNextExplicitCallUsesNewTransport() async throws {
        let requestIDs = LockedRequestIDs(["failed-id", "success-id"])
        let factory = RecordingTransportFactory(outcomes: [
            .failure(.daemonUnavailable),
            .success(response(id: "success-id", result: #"{"message":"pong"}"#)),
        ])
        let client = makeClient(requestIDs: requestIDs, factory: factory)
        let endpoint = try EntryCoreEndpoint(path: endpointPath)

        await assertError(.daemonUnavailable) {
            try await client.ping(endpoint)
        }
        XCTAssertEqual(factory.creationCount, 1)
        XCTAssertEqual(factory.requestCount, 1)

        let result = try await client.ping(endpoint)
        XCTAssertEqual(result, EntryCorePingResult())
        XCTAssertEqual(factory.creationCount, 2)
        XCTAssertEqual(factory.requestCount, 2)
        XCTAssertEqual(factory.requests.compactMap(requestID), ["failed-id", "success-id"])
    }

    func testPreservesEveryTransportAndDecoderErrorCategory() async throws {
        let transportErrors: [EntryCoreClientError] = [
            .daemonUnavailable,
            .timedOut(.connect),
            .timedOut(.write),
            .timedOut(.read),
            .cancelled,
            .transport(.connect),
            .transport(.write),
            .transport(.read),
            .responseTooLarge,
        ]
        let endpoint = try EntryCoreEndpoint(path: endpointPath)
        for expected in transportErrors {
            let factory = RecordingTransportFactory(outcomes: [.failure(expected)])
            let client = makeClient(requestIDs: LockedRequestIDs(["active-id"]), factory: factory)
            await assertError(expected) {
                try await client.ping(endpoint)
            }
            XCTAssertEqual(factory.creationCount, 1)
            XCTAssertEqual(factory.requestCount, 1)
        }

        let wrongProtocol =
            #"{"request_id":"active-id","protocol_version":2,"# +
            #""ok":true,"result":{"message":"pong"}}"#
        let decoderCases: [(EntryCoreClientError, Data)] = [
            (.malformedResponse, Data([0xFF])),
            (.protocolMismatch, Data(wrongProtocol.utf8)),
            (
                .requestIDMismatch,
                response(id: "other-id", result: #"{"message":"pong"}"#),
            ),
            (
                .server(.internalError),
                failure(
                    id: "active-id",
                    code: "internal_error",
                    message: "private server detail",
                ),
            ),
        ]
        for (expected, wire) in decoderCases {
            let factory = RecordingTransportFactory(outcomes: [.success(wire)])
            let client = makeClient(requestIDs: LockedRequestIDs(["active-id"]), factory: factory)
            await assertError(expected) {
                try await client.ping(endpoint)
            }
        }
    }

    func testPublicErrorsDoNotDescribeSensitiveWireValues() async throws {
        let sensitiveValues = [endpointPath, "secret-request-id", "secret-server-message", "secret-wire-value"]
        let cases: [(EntryCoreClientError, Data)] = [
            (.malformedResponse, Data("secret-wire-value".utf8)),
            (.requestIDMismatch, response(id: "other-secret-id", result: #"{"message":"pong"}"#)),
            (.server(.internalError), failure(
                id: "secret-request-id",
                code: "internal_error",
                message: "secret-server-message",
            )),
        ]

        let endpoint = try EntryCoreEndpoint(path: endpointPath)
        for (expected, wire) in cases {
            let factory = RecordingTransportFactory(outcomes: [.success(wire)])
            let client = makeClient(requestIDs: LockedRequestIDs(["secret-request-id"]), factory: factory)
            do {
                _ = try await client.ping(endpoint)
                XCTFail("Expected error")
            } catch {
                XCTAssertEqual(error as? EntryCoreClientError, expected)
                let description = String(describing: error)
                for sensitiveValue in sensitiveValues {
                    XCTAssertFalse(description.contains(sensitiveValue))
                }
            }
        }
    }

    private func makeClient(
        requestIDs: LockedRequestIDs,
        factory: RecordingTransportFactory,
    ) -> EntryCoreClient {
        EntryCoreClient.makeLive(
            requestID: requestIDs.next,
            makeTransport: factory.makeTransport,
        )
    }

    private func assertRequest(
        _ data: Data,
        id: String,
        method: EntryCoreMethod,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line,
        )
        XCTAssertEqual(
            Set(object.keys),
            ["request_id", "method", "params", "protocol_version"],
            file: file,
            line: line,
        )
        XCTAssertEqual(object["request_id"] as? String, id, file: file, line: line)
        XCTAssertEqual(object["method"] as? String, method.rawValue, file: file, line: line)
        XCTAssertEqual(object["protocol_version"] as? Int, 1, file: file, line: line)
        XCTAssertEqual((object["params"] as? [String: Any])?.count, 0, file: file, line: line)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
        XCTAssertFalse(text.contains(" "), file: file, line: line)
        XCTAssertFalse(text.contains("\n"), file: file, line: line)
    }

    private func requestID(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["request_id"] as? String
    }

    private func response(id: String, result: String) -> Data {
        let wire =
            #"{"request_id":"\#(id)","protocol_version":1,"# +
            #""ok":true,"result":\#(result)}"#
        return Data(wire.utf8)
    }

    private func failure(id: String, code: String, message: String) -> Data {
        let wire =
            #"{"request_id":"\#(id)","protocol_version":1,"ok":false,"# +
            #""error":{"code":"\#(code)","message":"\#(message)"}}"#
        return Data(wire.utf8)
    }

    private func assertError(
        _ expected: EntryCoreClientError,
        operation: () async throws -> some Any,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, expected, file: file, line: line)
        }
    }
}

private final class LockedRequestIDs: Sendable {
    private let values: OSAllocatedUnfairLock<[String]>

    init(_ values: [String]) {
        self.values = OSAllocatedUnfairLock(initialState: values)
    }

    func next() -> String {
        values.withLock { $0.removeFirst() }
    }
}

private final class RecordingTransportFactory: Sendable {
    typealias Outcome = Result<Data, EntryCoreClientError>

    private struct State {
        var outcomes: [Outcome]
        var creationCount = 0
        var requests: [Data] = []
        var endpoints: [EntryCoreEndpoint] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(outcomes: [Outcome]) {
        state = OSAllocatedUnfairLock(initialState: State(outcomes: outcomes))
    }

    var creationCount: Int {
        state.withLock { $0.creationCount }
    }

    var requestCount: Int {
        state.withLock { $0.requests.count }
    }

    var requests: [Data] {
        state.withLock { $0.requests }
    }

    var endpoints: [EntryCoreEndpoint] {
        state.withLock { $0.endpoints }
    }

    func makeTransport() -> EntryCoreTransportRequest {
        let outcome = state.withLock { state in
            state.creationCount += 1
            return state.outcomes.removeFirst()
        }
        return { request, endpoint in
            self.state.withLock { state in
                state.requests.append(request)
                state.endpoints.append(endpoint)
            }
            return try outcome.get()
        }
    }
}

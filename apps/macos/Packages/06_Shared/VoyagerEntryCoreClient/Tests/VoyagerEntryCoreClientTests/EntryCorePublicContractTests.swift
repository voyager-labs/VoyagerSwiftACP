import VoyagerEntryCoreClient
import XCTest

final class EntryCorePublicContractTests: XCTestCase {
    func testProtocolVersionAndMethodsExactlyMirrorProtocolV1() {
        XCTAssertEqual(EntryCoreProtocolVersion.v1.rawValue, 1)
        XCTAssertEqual(EntryCoreMethod.allCases.map(\.rawValue), ["ping", "health", "version"])
    }

    func testCanonicalResultsExactlyMirrorProtocolV1() throws {
        let ping = EntryCorePingResult()
        let health = EntryCoreHealthResult()
        let version = try EntryCoreVersionResult(appVersion: "0.1.0-dev")

        XCTAssertEqual(ping.message, "pong")
        XCTAssertEqual(health.status, "healthy")
        XCTAssertEqual(health.state, "running")
        XCTAssertEqual(version.appVersion, "0.1.0-dev")
        XCTAssertEqual(version.protocolVersion, .v1)
    }

    func testVersionResultRejectsEmptyAppVersion() {
        XCTAssertThrowsError(try EntryCoreVersionResult(appVersion: "")) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
    }

    func testKnownServerCodesExactlyMirrorProtocolV1() {
        XCTAssertEqual(
            EntryCoreServerErrorCode.allCases.map(\.rawValue),
            [
                "request_too_large",
                "invalid_request",
                "unsupported_protocol_version",
                "unknown_method",
                "internal_error",
            ],
        )
    }

    func testPublicErrorTaxonomyIsEquatable() {
        let errors: [EntryCoreClientError] = [
            .invalidEndpoint,
            .daemonUnavailable,
            .timedOut(.connect),
            .cancelled,
            .transport(.write),
            .responseTooLarge,
            .malformedResponse,
            .protocolMismatch,
            .requestIDMismatch,
            .server(.internalError),
        ]

        XCTAssertEqual(errors, errors)
        XCTAssertNotEqual(EntryCoreClientError.timedOut(.connect), .timedOut(.read))
        XCTAssertNotEqual(EntryCoreClientError.transport(.write), .transport(.read))
    }

    func testClosureClientIsSendableAndForwardsTypedCalls() async throws {
        let endpoint = try EntryCoreEndpoint(path: "/tmp/entry-core.sock")
        let client = EntryCoreClient(
            ping: { receivedEndpoint in
                XCTAssertEqual(receivedEndpoint, endpoint)
                return EntryCorePingResult()
            },
            health: { receivedEndpoint in
                XCTAssertEqual(receivedEndpoint, endpoint)
                return EntryCoreHealthResult()
            },
            version: { receivedEndpoint in
                XCTAssertEqual(receivedEndpoint, endpoint)
                return try EntryCoreVersionResult(appVersion: "dev")
            },
        )
        requireSendable(client)

        let ping = try await client.ping(endpoint)
        let health = try await client.health(endpoint)
        let version = try await client.version(endpoint)

        XCTAssertEqual(ping, EntryCorePingResult())
        XCTAssertEqual(health, EntryCoreHealthResult())
        XCTAssertEqual(version, try EntryCoreVersionResult(appVersion: "dev"))
    }

    private func requireSendable(_: some Sendable) {}
}

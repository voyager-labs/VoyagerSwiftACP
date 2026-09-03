import VoyagerEntryCoreClient
import XCTest

final class EntryCorePublicContractFlowTests: XCTestCase {
    func testMethodsMatchCanonicalContract() {
        XCTAssertEqual(EntryCoreMethod.allCases.map(\.rawValue), [
            "ping", "health", "version",
            "property.definition.list", "property.definition.create", "property.definition.update",
            "property.definition.disable",
            "property.option.create", "property.option.update", "property.option.reorder", "property.option.disable",
            "property.assignment.list", "property.change.prepare", "property.change.execute",
            "property.condition.query",
        ])
    }

    func testCanonicalResultsMatchContract() throws {
        let ping = EntryCorePingResult()
        let health = EntryCoreHealthResult()
        let version = try EntryCoreVersionResult(appVersion: "0.1.0-dev")

        XCTAssertEqual(ping.message, "pong")
        XCTAssertEqual(health.status, "healthy")
        XCTAssertEqual(health.state, "running")
        XCTAssertEqual(version.appVersion, "0.1.0-dev")
    }

    func testVersionResultRejectsEmptyAppVersion() {
        XCTAssertThrowsError(try EntryCoreVersionResult(appVersion: "")) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
    }

    func testKnownServerCodesMatchCanonicalContract() {
        XCTAssertEqual(
            EntryCoreServerErrorCode.allCases.map(\.rawValue),
            [
                "request_too_large",
                "invalid_request",
                "unknown_method",
                "invalid_path", "mount_not_found", "source_not_found", "invalid_selector", "context_mismatch",
                "scope_too_large", "invalid_page_token", "permission_denied", "source_unavailable",
                "source_runtime_unavailable",
                "source_deleted",
                "entry_not_found", "unsupported", "conflict", "adapter_failure", "property_not_found",
                "response_too_large",
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
            .localValidation,
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

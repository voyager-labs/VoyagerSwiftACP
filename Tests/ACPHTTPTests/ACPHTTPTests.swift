@testable import ACP
@testable import ACPHTTP
@testable import ACPModel
import XCTest

final class ACPHTTPTests: XCTestCase {
    // MARK: - WebSocketTransport Tests

    func testWebSocketTransportCreation() async throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:8080"))
        let transport = WebSocketTransport(url: url)

        let isConnected = await transport.isConnected
        XCTAssertFalse(isConnected)
    }

    func testWebSocketTransportMessageStream() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:8080"))
        let transport = WebSocketTransport(url: url)

        // Verify the messages stream exists
        _ = transport.messages
        XCTAssert(true, "Messages stream should be available")
    }

    // MARK: - Integration Tests

    func testTransportProtocolConformance() throws {
        let url = try XCTUnwrap(URL(string: "ws://localhost:8080"))
        let transport = WebSocketTransport(url: url)

        // Verify Transport protocol conformance
        let _: any Transport = transport
        XCTAssert(true, "WebSocketTransport conforms to Transport protocol")
    }

    /// A receive failure must surface as read-failure termination evidence, not
    /// as a generic closure, so clients can recover on typed evidence.
    func testReceiveFailurePreservesTerminationEvidence() async throws {
        // Port 1 is refused immediately on localhost, driving the receive
        // error path without an external server.
        let url = try XCTUnwrap(URL(string: "ws://127.0.0.1:1/acp"))
        let transport = WebSocketTransport(url: url)
        try await transport.connect()

        for await _ in transport.messages {}

        let termination = await transport.termination
        let evidence = try XCTUnwrap(termination)
        guard case let .failure(failure) = evidence.reason else {
            return XCTFail("Expected failure evidence, got \(evidence.reason)")
        }
        guard case .read = failure else {
            return XCTFail("Expected read failure, got \(failure)")
        }
        let isConnected = await transport.isConnected
        XCTAssertFalse(isConnected)
    }
}

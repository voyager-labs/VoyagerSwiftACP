@testable import ACP
import ACPModel
import XCTest

final class ACPSessionLoadingTests: XCTestCase {
    private func makeReadyClient(
        _ transport: ScriptedTransport,
        configuration: ClientConfiguration = .default,
    ) async throws -> Client {
        let client = Client(transport: transport, configuration: configuration)
        try await client.start()
        let initialization = spawnInitializeTask(
            client,
            capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: true,
            ),
        )
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 1, result: TestFrames.initializeResult(version: 1)))
        _ = try await initialization.value
        return client
    }

    func testFailedLoadDoesNotRegisterSession() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let request = Task { try await client.loadSession(sessionId: SessionId("missing"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"not found"}}"#,
        )
        _ = await request.result
        let snapshot = await client.sessionSnapshot(for: SessionId("missing"))
        XCTAssertNil(snapshot)
        let pending = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 1) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"missing","update":{"sessionUpdate":"future_update"}}"#,
        ))
        guard case let .failure(error) = await pending.result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Failed load must no longer authorize updates") }
        _ = await client.shutdown()
    }

    /// S19: Load history arrives before the response and preserves wire order.
    func testLoadDeliversHistoryBeforeResponse() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = SessionId("restored")
        let load = Task { try await client.loadSession(sessionId: sessionId, cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        for text in ["first", "second"] {
            try await transport.pushJSON(TestFrames.notification(
                method: "session/update",
                params: #"{"sessionId":"restored","update":{"sessionUpdate":"agent_message_chunk","content":"#
                    + #"{"type":"text","text":"\#(text)"}}}"#,
            ))
        }
        try await transport.pushJSON(TestFrames.response(id: 2, result: "{}"))
        _ = try await load.value
        var updates = await client.notifications.makeAsyncIterator()
        for text in ["first", "second"] {
            let notification = await updates.next()
            let params = notification?.params?.value as? [String: Any]
            let update = params?["update"] as? [String: Any]
            let content = update?["content"] as? [String: Any]
            XCTAssertEqual(content?["text"] as? String, text)
        }
        let snapshot = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(snapshot?.state, .idle)
        _ = await client.shutdown()
    }

    /// S20: Caller cancellation removes permission to replay an unloaded session.
    func testCancelledLoadRejectsFurtherHistory() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let load = Task { try await client.loadSession(sessionId: SessionId("restored"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        load.cancel()
        _ = await load.result
        let pending = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 1) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"restored","update":{"sessionUpdate":"future_update"}}"#,
        ))
        guard case let .failure(error) = await pending.result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Cancelled load must no longer authorize updates") }
        let snapshot = await client.sessionSnapshot(for: SessionId("restored"))
        XCTAssertNil(snapshot)
        _ = await client.shutdown()
    }

    /// S21: A load deadline removes replay authorization and ignores a late success.
    func testTimedOutLoadRejectsLateHistory() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(
            transport, configuration: ClientConfiguration(requestTimeout: 0.1),
        )
        let load = Task { try await client.loadSession(sessionId: SessionId("restored"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        guard case let .failure(error) = await load.result,
              let clientError = error as? ClientError,
              case .requestTimeout = clientError
        else { return XCTFail("Expected load deadline") }
        let pending = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 1) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 2, result: "{}"))
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"restored","update":{"sessionUpdate":"future_update"}}"#,
        ))
        guard case let .failure(error) = await pending.result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Timed-out load must no longer authorize updates") }
        let snapshot = await client.sessionSnapshot(for: SessionId("restored"))
        XCTAssertNil(snapshot)
        _ = await client.shutdown()
    }

    /// S22: A pending load authorizes only the requested session ID.
    func testPendingLoadRejectsUnrelatedSessionHistory() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let load = Task { try await client.loadSession(sessionId: SessionId("restored"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"unrelated","update":{"sessionUpdate":"future_update"}}"#,
        ))
        guard case let .failure(error) = await load.result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Pending load must not authorize another session") }
        _ = await client.shutdown()
    }
}

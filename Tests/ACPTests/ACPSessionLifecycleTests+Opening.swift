@testable import ACP
import ACPModel
import XCTest

extension ACPSessionLifecycleTests {
    func testOpeningSessionAcceptsUpdatesBeforeResponse() async throws {
        for loading in [false, true] {
            let transport = ScriptedTransport()
            let client = try await makeReadyClient(transport)
            let stream = await client.notifications
            let collector = Task {
                var values: [String] = []
                for await notification in stream {
                    let data = try JSONEncoder().encode(notification.params)
                    let params = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let update = params?["update"] as? [String: Any],
                       let content = update["content"] as? [String: Any],
                       let text = content["text"] as? String { values.append(text) }
                }
                return values
            }
            let opening = Task {
                if loading {
                    _ = try await client.loadSession(sessionId: SessionId("early"), cwd: "/tmp")
                } else {
                    _ = try await client.newSession(workingDirectory: "/tmp")
                }
            }
            let frame = try await transport.nextSentFrame()
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
            for text in ["first", "second"] {
                try await transport.pushJSON(TestFrames.notification(
                    method: "session/update",
                    params: #"{"sessionId":"early","update":{"sessionUpdate":"agent_message_chunk","content":"#
                        + #"{"type":"text","text":""# + text + #""}}}"#,
                ))
            }
            try await transport.pushJSON(TestFrames.response(
                id: requestID(request.id),
                result: #"{"sessionId":"early"}"#,
            ))
            _ = try await opening.value
            _ = await client.shutdown()
            let values = try await collector.value
            XCTAssertEqual(values, ["first", "second"])
        }
    }

    func testOpeningUpdatesRespectBudget() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport, configuration: ClientConfiguration(notificationByteBudget: 1))
        let opening = Task { try await client.newSession(workingDirectory: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update", params: #"{"sessionId":"early","update":{"sessionUpdate":"future_update"}}"#,
        ))
        do {
            _ = try await opening.value
            XCTFail("Opening updates must be bounded")
        } catch let error as ClientError {
            guard case .protocolViolation = error else { return XCTFail("Unexpected error: \(error)") }
        }
        _ = await client.shutdown()
    }

    func testFailedOpeningDiscardsReplayAndAllowsNextOpening() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let stream = await client.notifications
        let collector = Task { var count = 0
            for await _ in stream {
                count += 1
            }
            return count
        }
        let opening = Task { try await client.loadSession(sessionId: SessionId("early"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update", params: #"{"sessionId":"early","update":{"sessionUpdate":"future_update"}}"#,
        ))
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"unavailable"}}"#)
        do { _ = try await opening.value
            XCTFail("Expected agent failure")
        } catch let error as ClientError {
            guard case .agentError = error else { return XCTFail("Unexpected error: \(error)") }
        }
        _ = try await createSession(client, transport)
        let failed = await client.sessionSnapshot(for: SessionId("early"))
        XCTAssertNil(failed)
        _ = await client.shutdown()
        let count = await collector.value
        XCTAssertEqual(count, 0)
    }

    func testConcurrentOpeningRejectedWithoutWritingAndCancellationReleasesGuard() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let opening = Task { try await client.newSession(workingDirectory: "/tmp") }
        _ = try await transport.nextSentFrame()
        let before = transport.allSentFrames().count
        do {
            _ = try await client.loadSession(sessionId: SessionId("other"), cwd: "/tmp")
            XCTFail("Overlapping session openings cannot correlate early updates")
        } catch let error as ClientError {
            guard case .invalidParams = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(transport.allSentFrames().count, before)
        opening.cancel()
        do { _ = try await opening.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        _ = try await createSession(client, transport)
        _ = await client.shutdown()
    }

    private actor NotificationRecorder {
        var count = 0
        func record() {
            count += 1
        }
    }

    func testNotificationHandlerCompletesBeforePromptResponse() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport, configuration: ClientConfiguration(notificationByteBudget: 1))
        let recorder = NotificationRecorder()
        try await client.setNotificationHandler { _ in
            try await Task.sleep(nanoseconds: 10_000_000)
            await recorder.record()
        }
        try await client.start()
        let initialization = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: #"{"protocolVersion":1,"agentCapabilities":{}}"#)
        _ = try await initialization.value
        _ = try await createSession(client, transport)
        let prompt = Task { try await client.sendPrompt(sessionId: SessionId("s1"), content: []) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update", params: #"{"sessionId":"s1","update":{"sessionUpdate":"future_update"}}"#,
        ))
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"end_turn"}"#))
        _ = try await prompt.value
        let count = await recorder.count
        XCTAssertEqual(count, 1)
        _ = await client.shutdown()
    }

    func testOpeningHandlerDrainsBeforeResponseAndRejectsLateInstallation() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        let recorder = NotificationRecorder()
        try await client.setNotificationHandler { _ in
            try await Task.sleep(nanoseconds: 10_000_000)
            await recorder.record()
        }
        try await client.start()
        let initialization = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: #"{"protocolVersion":1,"agentCapabilities":{}}"#)
        _ = try await initialization.value
        do {
            try await client.setNotificationHandler { _ in }
            XCTFail("A connected consumer cannot be replaced")
        } catch let error as ClientError {
            guard case .invalidParams = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let opening = Task { try await client.loadSession(sessionId: SessionId("early"), cwd: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update", params: #"{"sessionId":"early","update":{"sessionUpdate":"future_update"}}"#,
        ))
        try await transport.pushJSON(TestFrames.response(id: 2, result: "{}"))
        _ = try await opening.value
        let count = await recorder.count
        XCTAssertEqual(count, 1)
        _ = await client.shutdown()
    }

    func testOpeningHandlerFailureFailsRequestWithoutLeakingError() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.setNotificationHandler { _ in
            throw NSError(domain: "private-payload", code: 42)
        }
        try await client.start()
        let initialization = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: #"{"protocolVersion":1,"agentCapabilities":{}}"#)
        _ = try await initialization.value
        let opening = Task { try await client.newSession(workingDirectory: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update", params: #"{"sessionId":"early","update":{"sessionUpdate":"future_update"}}"#,
        ))
        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"early"}"#))
        do { _ = try await opening.value
            XCTFail("Expected handler failure")
        } catch let error as ClientError {
            guard case .protocolViolation = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertFalse(String(describing: error).contains("private-payload"))
        }
        _ = await client.shutdown()
    }
}

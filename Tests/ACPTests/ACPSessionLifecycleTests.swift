//
//  ACPSessionLifecycleTests.swift
//  ACPTests
//
//  T6: session registration, prompt turns, updates, and protocol cancellation.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPSessionLifecycleTests: XCTestCase {
    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

    private func requestID(_ id: RequestId) -> Int {
        if case let .number(value) = id {
            return value
        }
        return -1
    }

    @discardableResult
    private func respondToNextRequest(
        _ transport: ScriptedTransport,
        result: @autoclosure () throws -> String,
    ) async throws -> RequestId {
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        try await transport.pushJSON(TestFrames.response(id: requestID(request.id), result: result()))
        return request.id
    }

    private func makeReadyClient(
        _ transport: ScriptedTransport,
        initResult: String = #"{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"close":{}}}}"#,
        configuration: ClientConfiguration = .default,
    ) async throws -> Client {
        let client = Client(transport: transport, configuration: configuration)
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: initResult)
        _ = try await initTask.value
        return client
    }

    private func createSession(_ client: Client, _ transport: ScriptedTransport,
                               id: String = "s1") async throws -> SessionId
    {
        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await respondToNextRequest(transport, result: #"{"sessionId":"\#(id)"}"#)
        return try await task.value.sessionId
    }

    func testInvalidRequestTimeoutsFailBeforeWriting() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let before = transport.allSentFrames().count
        for timeout in [-1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            do {
                _ = try await client.newSession(workingDirectory: "/tmp", timeout: timeout)
                XCTFail("Invalid timeout must fail")
            } catch let error as ClientError {
                guard case .invalidParams = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        XCTAssertEqual(transport.allSentFrames().count, before)
        _ = await client.shutdown()
    }

    func testRelativeWorkingDirectoryFailsBeforeWriting() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let before = transport.allSentFrames().count
        for cwd in ["", "relative/path", "~/Documents"] {
            do {
                _ = try await client.newSession(workingDirectory: cwd)
                XCTFail("Relative cwd must fail")
            } catch let error as ClientError {
                guard case .invalidParams = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        XCTAssertEqual(transport.allSentFrames().count, before)
        _ = await client.shutdown()
    }

    func testInvalidCancellationGraceFailsBeforeWritingCancel() async throws {
        for grace in [-1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            let transport = ScriptedTransport()
            let client = try await makeReadyClient(
                transport, configuration: ClientConfiguration(cancellationGrace: grace),
            )
            let sessionId = try await createSession(client, transport)
            let prompt = Task { try await client.sendPrompt(sessionId: sessionId, content: []) }
            _ = try await transport.nextSentFrame()
            let before = transport.allSentFrames().count
            do {
                try await client.cancelSession(sessionId: sessionId)
                XCTFail("Invalid cancellation grace must fail")
            } catch let error as ClientError {
                guard case .invalidParams = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertEqual(transport.allSentFrames().count, before)
            _ = await client.shutdown()
            _ = await prompt.result
        }
    }

    func testCallerCancellationGraceClosesUnresponsiveConnection() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(
            transport, configuration: ClientConfiguration(cancellationGrace: 0.01),
        )
        let sessionId = try await createSession(client, transport)
        let prompt = Task { try await client.sendPrompt(sessionId: sessionId, content: []) }
        _ = try await transport.nextSentFrame()
        let pending = Task { try await client.newSession(workingDirectory: "/other", timeout: 1) }
        _ = try await transport.nextSentFrame()
        prompt.cancel()
        _ = await prompt.result
        _ = try await transport.nextSentFrame()
        let result = await pending.result
        guard case let .failure(error) = result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Grace must fail pending request with protocol violation") }
        _ = await client.shutdown()
        let state = await client.state
        XCTAssertTrue(state == .failed || state == .closed)
    }

    func testNotificationByteBudgetRejectsUnconsumedUpdate() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(
            transport, configuration: ClientConfiguration(notificationByteBudget: 1),
        )
        _ = try await createSession(client, transport)
        let pending = Task { try await client.newSession(workingDirectory: "/other", timeout: 1) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"future_update"}}"#,
        ))
        let result = await pending.result
        guard case let .failure(error) = result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Expected protocol failure") }
        _ = await client.shutdown()
    }

    func testUnknownSessionFutureUpdateFailsConnection() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let pending = Task { try await client.newSession(workingDirectory: "/other", timeout: 1) }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"unknown","update":{"sessionUpdate":"future_update"}}"#,
        ))
        let result = await pending.result
        guard case let .failure(error) = result,
              let clientError = error as? ClientError,
              case .protocolViolation = clientError
        else { return XCTFail("Expected protocol failure") }
        _ = await client.shutdown()
    }

    func testCallerCancellationRetainsWireTurn() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)
        let prompt = Task { try await client.sendPrompt(sessionId: sessionId, content: []) }
        _ = try await transport.nextSentFrame()
        prompt.cancel()
        do {
            _ = try await prompt.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let frame = try await transport.nextSentFrame()
        let cancel = try JSONDecoder().decode(JSONRPCNotification.self, from: frame)
        XCTAssertEqual(cancel.method, "session/cancel")
        let cancelling = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(cancelling?.state, .cancelling)
        do {
            _ = try await client.sendPrompt(sessionId: sessionId, content: [])
            XCTFail("Wire turn must remain busy")
        } catch let error as ClientError {
            guard case .sessionBusy = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"cancelled"}"#))
        let barrier = Task { try await client.newSession(workingDirectory: "/tmp") }
        _ = try await respondToNextRequest(transport, result: #"{"sessionId":"barrier"}"#)
        _ = try await barrier.value
        let idle = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(idle?.state, .idle)
        XCTAssertEqual(idle?.lastStopReason, .cancelled)
        _ = await client.shutdown()
    }

    func testMalformedKnownUpdateFailsConnection() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        _ = try await createSession(client, transport)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk"}}}"#,
        )
        let barrier = Task {
            try await client.sendRequest(method: "test/barrier", params: [String: String](), timeout: 0.1)
        }
        _ = await barrier.result
        let state = await client.state
        XCTAssertEqual(state, .failed)
        _ = await client.shutdown()
    }

    func testNewSessionServerErrorPreservesConnection() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let request = Task { try await client.newSession(workingDirectory: "/tmp") }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"retry"}}"#,
        )
        do {
            _ = try await request.value
            XCTFail("Expected server error")
        } catch let error as ClientError {
            guard case .agentError = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let state = await client.state
        XCTAssertEqual(state, .ready)
        _ = await client.shutdown()
    }

    /// S01
    func testCreatesSessionFromAgentID() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport, id: "agent-made-42")

        XCTAssertEqual(sessionId.value, "agent-made-42")
        let snapshot = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(snapshot?.state, .idle)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S02
    func testPromptSuccessReturnsStopReason() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let task = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "hi"))], timeout: 5)
        }
        _ = try await respondToNextRequest(transport, result: #"{"stopReason":"end_turn"}"#)
        let response = try await task.value
        XCTAssertEqual(response.stopReason, .endTurn)

        let snapshot = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(snapshot?.state, .idle)
        XCTAssertEqual(snapshot?.lastStopReason, .endTurn)

        await transport.finish()
        _ = await client.shutdown()
    }

    private func collectFirstNotification(from stream: AsyncStream<JSONRPCNotification>,
                                          matching method: String) -> Task<JSONRPCNotification?, Never>
    {
        Task {
            for await notification in stream {
                if notification.method == method {
                    return notification
                }
            }
            return nil
        }
    }

    /// S03
    func testDeliversSessionUpdate() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        _ = try await createSession(client, transport)

        let notifications = await client.notifications
        let collector = collectFirstNotification(from: notifications, matching: "session/update")

        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"chunk" }}}"#,
        ))

        let notificationValue = await collector.value
        let notification = try XCTUnwrap(notificationValue, "expected session/update delivery")
        let params = try XCTUnwrap(notification.params)
        let dict = try XCTUnwrap(params.value as? [String: Any])
        XCTAssertEqual(dict["sessionId"] as? String, "s1")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S04
    func testUpdatesPreserveWireOrder() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let notifications = await client.notifications
        let collector = Task {
            var updates: [Int] = []
            for await notification in notifications where notification.method == "session/update" {
                if let data = try? JSONEncoder().encode(notification.params),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let update = dict["update"] as? [String: Any],
                   let chunk = update["content"] as? [String: Any],
                   let text = chunk["text"] as? String
                {
                    updates.append(Int(text) ?? -1)
                }
                if updates.count == 3 {
                    return updates
                }
            }
            return updates
        }

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()

        // Updates must be enqueued before the prompt response completes.
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"1"}}}"#,
        ))
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"2"}}}"#,
        ))
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"3"}}}"#,
        ))
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"end_turn"}"#))

        let response = try await promptTask.value
        XCTAssertEqual(response.stopReason, .endTurn)

        let updateValue = await collector.value
        let updates = try XCTUnwrap(updateValue)
        XCTAssertEqual(updates, [1, 2, 3])

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S05
    func testUnknownSessionUpdateFailsConnection() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        _ = try await createSession(client, transport, id: "s1")

        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"never-registered","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ghost" }}}"#,
        ))

        // The connection fails with a typed protocol violation.
        for _ in 0 ..< 50 {
            let state = await client.state
            if state == .failed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let state = await client.state
        XCTAssertEqual(state, .failed)

        _ = await client.shutdown()
    }

    /// S06 + S07
    func testCancelIsIdempotentNotification() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()

        try await client.cancelSession(sessionId: sessionId)
        // Repeated cancel sends nothing more and succeeds.
        try await client.cancelSession(sessionId: sessionId)

        // Allow the wire to settle, then inspect the cancel frame.
        try await Task.sleep(nanoseconds: 100_000_000)
        let cancelFrame = try XCTUnwrap(
            transport.allSentFrames().last { frame in
                guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
                    return false
                }
                return object["method"] as? String == "session/cancel"
            },
            "expected a session/cancel notification on the wire",
        )
        let cancelObject = try JSONSerialization.jsonObject(with: cancelFrame) as? [String: Any]
        XCTAssertNil(cancelObject?["id"], "session/cancel must be a notification without id")

        // Terminal response returns the session to idle.
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"cancelled"}"#))
        let response = try await promptTask.value
        XCTAssertEqual(response.stopReason, .cancelled)

        let snapshot = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(snapshot?.state, .idle)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S08
    func testPromptAfterCancelledTurnIsAllowed() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let firstPrompt = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"cancelled"}"#))
        _ = try await firstPrompt.value

        let secondPrompt = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "again"))], timeout: 5)
        }
        _ = try await respondToNextRequest(transport, result: #"{"stopReason":"end_turn"}"#)
        let second = try await secondPrompt.value
        XCTAssertEqual(second.stopReason, .endTurn)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S09
    func testPromptAfterSessionCloseRejected() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let closeTask = Task { try await client.closeSession(sessionId: sessionId) }
        _ = try await respondToNextRequest(transport, result: "{}")
        _ = try await closeTask.value

        do {
            _ = try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
            XCTFail("expected sessionClosed")
        } catch let error as ClientError {
            guard case .sessionClosed = error else {
                return XCTFail("expected sessionClosed, got \(error)")
            }
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// Typed session APIs refuse to reach the wire before the initialize
    /// handshake reaches `.ready`.
    func testSessionApiBeforeReadyIsLocalRefusal() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        do {
            _ = try await client.setMode(sessionId: SessionId("s1"), modeId: "code")
            XCTFail("expected notInitialized")
        } catch let error as ClientError {
            guard case .notInitialized = error else {
                return XCTFail("expected notInitialized, got \(error)")
            }
        }
        XCTAssertTrue(transport.allSentFrames().isEmpty, "the refusal must not write to the wire")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// An agent error on `session/close` must surface as a thrown agent error,
    /// never as an empty-success conversion of the session state.
    func testCloseSessionErrorSurfacesAsAgentError() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let closeTask = Task { try await client.closeSession(sessionId: sessionId) }
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":\#(requestID(request.id)),"error":{"code":-32050,"message":"close failed"}}"#,
        )

        do {
            _ = try await closeTask.value
            XCTFail("expected agentError")
        } catch let error as ClientError {
            guard case .agentError = error else {
                return XCTFail("expected agentError, got \(error)")
            }
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// A nonempty authenticate result that fails to decode is a protocol
    /// failure; it must never be reported as an authenticated success.
    func testMalformedAuthenticateResultThrows() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let authTask = Task { try await client.authenticate(authMethodId: "codex") }
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":\#(requestID(request.id)),"result":{"unexpected":true}}"#,
        )

        do {
            _ = try await authTask.value
            XCTFail("expected invalidResponse for a malformed auth result")
        } catch let error as ClientError {
            guard case .invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S10
    func testPromptWhileCancellingRejected() async throws {
        let transport = ScriptedTransport()
        let client = Client(
            transport: transport,
            configuration: ClientConfiguration(requestTimeout: 5, cancellationGrace: 0.6),
        )
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(
            transport,
            result: #"{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"close":{}}}}"#,
        )
        _ = try await initTask.value

        let sessionId = try await createSession(client, transport)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()

        try await client.cancelSession(sessionId: sessionId)

        // While the turn is cancelling, a second prompt is busy.
        do {
            _ = try await client.sendPrompt(
                sessionId: sessionId,
                content: [.text(TextContent(text: "nope"))],
                timeout: 5,
            )
            XCTFail("expected sessionBusy")
        } catch let error as ClientError {
            guard case .sessionBusy = error else {
                return XCTFail("expected sessionBusy, got \(error)")
            }
        }

        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"cancelled"}"#))
        _ = try await promptTask.value

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S11
    func testConcurrentSessionsAreIndependent() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionA = try await createSession(client, transport, id: "a")
        let sessionB = try await createSession(client, transport, id: "b")

        let promptA = Task {
            try await client.sendPrompt(sessionId: sessionA, content: [.text(TextContent(text: "a"))], timeout: 5)
        }
        let promptB = Task {
            try await client.sendPrompt(sessionId: sessionB, content: [.text(TextContent(text: "b"))], timeout: 5)
        }

        // Responses arrive in either order; each caller gets its own result.
        var remaining: [Data] = try await [transport.nextSentFrame(), transport.nextSentFrame()]
        for frame in remaining {
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
            let sessionId = (request.params.flatMap { $0.value as? [String: Any] })?["sessionId"] as? String
            try await transport.pushJSON(TestFrames.response(
                id: requestID(request.id),
                result: #"{"stopReason":"end_turn","_meta":{"who":"\#(sessionId ?? "")"}}"#,
            ))
        }
        remaining.removeAll()

        let responseA = try await promptA.value
        let responseB = try await promptB.value
        XCTAssertEqual(responseA.stopReason, .endTurn)
        XCTAssertEqual(responseB.stopReason, .endTurn)

        let snapshotA = await client.sessionSnapshot(for: sessionA)
        let snapshotB = await client.sessionSnapshot(for: sessionB)
        XCTAssertEqual(snapshotA?.state, .idle)
        XCTAssertEqual(snapshotB?.state, .idle)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S12
    func testDuplicateSessionIDRejected() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        _ = try await createSession(client, transport, id: "dup")

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await respondToNextRequest(transport, result: #"{"sessionId":"dup"}"#)

        do {
            _ = try await task.value
            XCTFail("expected protocol failure")
        } catch let error as ClientError {
            guard case .protocolViolation = error else {
                return XCTFail("expected protocolViolation, got \(error)")
            }
        }

        // The connection is failed by the violation.
        for _ in 0 ..< 50 {
            let state = await client.state
            if state == .failed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let state = await client.state
        XCTAssertEqual(state, .failed)

        _ = await client.shutdown()
    }

    /// S13
    func testUnknownUpdateVariantRemainsRaw() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport, id: "s1")

        let notifications = await client.notifications
        let collector = collectFirstNotification(from: notifications, matching: "session/update")

        // A future sessionUpdate variant passes through raw, unchanged, and does
        // not affect connection health.
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"telepathy_broadcast","thoughts":42}}"#,
        ))

        let notificationValue = await collector.value
        let notification = try XCTUnwrap(notificationValue)
        let data = try JSONEncoder().encode(XCTUnwrap(notification.params))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let update = try XCTUnwrap(dict["update"] as? [String: Any])
        XCTAssertEqual(update["sessionUpdate"] as? String, "telepathy_broadcast")
        XCTAssertEqual(update["thoughts"] as? Int, 42)

        // The connection is still healthy: a prompt still works.
        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "hi"))], timeout: 5)
        }
        _ = try await respondToNextRequest(transport, result: #"{"stopReason":"end_turn"}"#)
        _ = try await promptTask.value

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S14
    func testServerErrorRemainsServerError() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "hi"))], timeout: 5)
        }
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)

        try await transport
            .pushJSON(
                #"{"jsonrpc":"2.0","id":\#(requestID(request.id)),"error":{"code":-32001,"message":"provider down","data":{"details":"retry later"}}}"#,
            )

        do {
            _ = try await promptTask.value
            XCTFail("expected agent error")
        } catch let error as ClientError {
            guard case let .agentError(rpcError) = error else {
                return XCTFail("expected agentError, got \(error)")
            }
            XCTAssertEqual(rpcError.code, -32001)
            XCTAssertEqual(rpcError.message, "provider down")
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S15
    func testCancelResolvesPendingPermissionExactlyOnce() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport, id: "s1")

        let delegate = RecordingClientDelegate()
        await client.setDelegate(delegate)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()

        // The agent asks for permission and blocks the prompt response.
        try await transport.pushJSON(TestFrames.request(
            id: 500,
            method: "session/request_permission",
            params: #"{"sessionId":"s1","options":[{"kind":"allow_once","name":"Allow","optionId":"allow"}],"toolCall":{"toolCallId":"tc-1","status":"pending","title":"t"}}"#,
        ))
        await delegate.waitUntilPermissionRequested()

        // Cancelling the session resolves the pending permission exactly once
        // with a cancelled outcome on the wire.
        try await client.cancelSession(sessionId: sessionId)
        try await Task.sleep(nanoseconds: 100_000_000)

        let cancelledResponses = transport.allSentFrames().filter { frame in
            guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                  let result = object["result"] as? [String: Any],
                  let outcome = result["outcome"] as? [String: Any],
                  let outcomeKind = outcome["outcome"] as? String
            else {
                return false
            }
            return outcomeKind == "cancelled"
        }
        XCTAssertEqual(cancelledResponses.count, 1)

        // The late delegate resolution must not write another response.
        await delegate.resolvePermission(RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow")))
        try await Task.sleep(nanoseconds: 100_000_000)
        let cancelledFrames = transport.allSentFrames().filter { (frame: Data) -> Bool in
            guard let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                  let result = object["result"] as? [String: Any],
                  let outcome = result["outcome"] as? [String: Any],
                  let outcomeKind = outcome["outcome"] as? String
            else {
                return false
            }
            return outcomeKind == "cancelled"
        }
        XCTAssertEqual(cancelledFrames.count, 1)

        _ = await promptTask.result

        await transport.finish()
        _ = await client.shutdown()
    }

    /// S17
    func testTerminalResponseFollowsPendingUpdates() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        let sessionId = try await createSession(client, transport)

        let notifications = await client.notifications
        let collector = Task {
            var updates: [Int] = []
            for await notification in notifications where notification.method == "session/update" {
                if let data = try? JSONEncoder().encode(notification.params),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let update = dict["update"] as? [String: Any],
                   let text = (update["content"] as? [String: Any])?["text"] as? String
                {
                    updates.append(Int(text) ?? -1)
                }
                if updates.count == 1 {
                    return updates
                }
            }
            return updates
        }

        let promptTask = Task {
            try await client.sendPrompt(sessionId: sessionId, content: [.text(TextContent(text: "go"))], timeout: 5)
        }
        _ = try await transport.nextSentFrame()

        try await client.cancelSession(sessionId: sessionId)
        try await transport.pushJSON(TestFrames.notification(
            method: "session/update",
            params: #"{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"7"}}}"#,
        ))
        try await transport.pushJSON(TestFrames.response(id: 3, result: #"{"stopReason":"cancelled"}"#))

        let response = try await promptTask.value
        XCTAssertEqual(response.stopReason, .cancelled)

        let updateValue = await collector.value
        let updates = try XCTUnwrap(updateValue)
        XCTAssertEqual(updates, [7])

        await transport.finish()
        _ = await client.shutdown()
    }
}

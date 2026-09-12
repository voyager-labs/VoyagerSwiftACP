@testable import ACP
import XCTest

final class ACPAgentTests: XCTestCase {
    func testMalformedJSONAnswersParseErrorAndCloses() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        try await transport.pushFrame(Data("{broken".utf8))
        await transport.finish()

        await agent.start()

        let frames = transport.allSentFrames()
        XCTAssertEqual(frames.count, 1)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: XCTUnwrap(frames.first))
        XCTAssertEqual(response.id, .null)
        XCTAssertEqual(response.error?.code, -32700)
        XCTAssertTrue(transport.wasClosed)
    }

    func testInvalidKnownNotificationsFailPendingWithoutResponse() async throws {
        let notifications = [
            #"{"jsonrpc":"2.0","method":"session/cancel","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":7}}"#,
            #"{"jsonrpc":"2.0","method":"$/cancel_request","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"document/didOpen","params":{}}"#,
        ]
        for notification in notifications {
            let transport = ScriptedTransport()
            let agent = Agent(transport: transport)
            let pending = Task { try await agent.connectMcp(serverId: McpServerAcpId("server")) }
            _ = try await transport.nextSentFrame()
            try await transport.pushJSON(notification)
            await transport.finish()

            await agent.start()

            do {
                _ = try await pending.value
                XCTFail("Invalid notification must fail pending request")
            } catch let error as ClientError {
                guard case .protocolViolation = error else {
                    return XCTFail("Expected protocol violation, got \(error)")
                }
            }
            XCTAssertTrue(transport.wasClosed)
            XCTAssertEqual(transport.allSentFrames().count, 1, "Notifications must not receive responses")
        }
    }

    func testInvalidBooleanIDIsNotRecoveredAsInteger() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":true,"method":"initialize","params":{}}"#)
        await transport.finish()
        await agent.start()
        let frame = try XCTUnwrap(transport.allSentFrames().first)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: frame)
        XCTAssertEqual(response.id, .null)
        XCTAssertEqual(response.error?.code, -32600)
    }

    func testAgentNegotiatesVersionOneAndPreservesDelegateMetadata() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = EchoVersionAgentDelegate()
        await agent.setDelegate(delegate)
        let start = Task { await agent.start() }
        try await transport.pushJSON(TestFrames.request(
            id: 1, method: "initialize", params: #"{"protocolVersion":2,"clientCapabilities":{}}"#,
        ))
        let frame = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: frame)
        let result = try XCTUnwrap(response.result)
        let initialized = try JSONDecoder().decode(InitializeResponse.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(initialized.protocolVersion, 1)
        XCTAssertEqual(initialized._meta?["marker"]?.value as? String, "preserved")
        await transport.finish()
        await start.value
    }

    /// Completes the initialize handshake so session-scoped requests route.
    private func pushInitialize(_ transport: ScriptedTransport, id: Int = 1) async throws {
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":\#(id),"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}"#,
        )
        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        XCTAssertNil(response.error)
    }

    func testCloseSessionInvokesCancelBeforeClose() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport)

        let request = JSONRPCRequest(
            id: .number(1),
            method: "session/close",
            params: AnyCodable(["sessionId": "session-123"]),
        )
        let requestData = try JSONEncoder().encode(request)
        try await transport.pushFrame(requestData)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        let events = await delegate.recordedEvents()

        XCTAssertEqual(response.id, .number(1))
        XCTAssertNil(response.error)
        XCTAssertEqual(events, [
            "initialize:1",
            "cancel:session-123",
            "close:session-123",
        ])

        await transport.finish()
        _ = await startTask.result
    }

    func testResumeSessionRoutesToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport)

        let request = JSONRPCRequest(
            id: .number(2),
            method: "session/resume",
            params: AnyCodable([
                "sessionId": "session-123",
                "cwd": "/tmp/project",
                "additionalDirectories": ["/tmp/shared"],
            ] as [String: any Sendable]),
        )
        let requestData = try JSONEncoder().encode(request)
        try await transport.pushFrame(requestData)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        let events = await delegate.recordedEvents()
        let result = try XCTUnwrap(response.result)
        let resultData = try JSONEncoder().encode(result)
        let resumeResponse = try JSONDecoder().decode(ResumeSessionResponse.self, from: resultData)

        XCTAssertEqual(response.id, .number(2))
        XCTAssertNil(response.error)
        XCTAssertEqual(events, [
            "initialize:1",
            "resume:session-123:/tmp/project:/tmp/shared",
        ])
        XCTAssertEqual(resumeResponse.modes?.currentModeId, "chat")

        await transport.finish()
        _ = await startTask.result
    }

    func testDeleteSessionRoutesToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport)

        let request = JSONRPCRequest(
            id: .number(3),
            method: "session/delete",
            params: AnyCodable(["sessionId": "session-123"]),
        )
        let requestData = try JSONEncoder().encode(request)
        try await transport.pushFrame(requestData)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        let events = await delegate.recordedEvents()

        XCTAssertEqual(response.id, .number(3))
        XCTAssertNil(response.error)
        XCTAssertEqual(events, [
            "initialize:1",
            "delete:session-123",
        ])

        await transport.finish()
        _ = await startTask.result
    }

    func testLogoutRoutesWithoutParamsToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        let request = JSONRPCRequest(
            id: .number(4),
            method: "logout",
            params: nil,
        )
        let requestData = try JSONEncoder().encode(request)
        try await transport.pushFrame(requestData)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        let events = await delegate.recordedEvents()

        XCTAssertEqual(response.id, .number(4))
        XCTAssertNil(response.error)
        XCTAssertEqual(events, ["logout"])

        // Strict ACP v1 wire contract: `params: null` is neither omitted nor
        // structured, so the request is rejected with -32600 instead of routed.
        // The request is expressed as raw wire JSON because the typed model now
        // refuses to encode that shape at all.
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":5,"method":"logout","params":null}"#)

        let nullParamsResponseData = try await transport.nextSentFrame()
        let nullParamsResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: nullParamsResponseData)
        let nullParamsEvents = await delegate.recordedEvents()

        XCTAssertEqual(nullParamsResponse.id, .number(5))
        XCTAssertEqual(nullParamsResponse.error?.code, -32600)
        XCTAssertEqual(nullParamsEvents, ["logout"])

        await transport.finish()
        _ = await startTask.result
    }

    func testUnknownMethodAnswers32601AndKeepsConnection() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":10,"method":"totally/unknown","params":{}}"#)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        XCTAssertEqual(response.id, .number(10))
        XCTAssertEqual(response.error?.code, -32601)

        // The connection is still usable: a known method still routes.
        let logoutRequest = JSONRPCRequest(id: .number(11), method: "logout", params: nil)
        try await transport.pushFrame(JSONEncoder().encode(logoutRequest))
        let logoutResponseData = try await transport.nextSentFrame()
        let logoutResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: logoutResponseData)
        XCTAssertNil(logoutResponse.error)

        await transport.finish()
        _ = await startTask.result
    }

    func testInvalidParamsAnswers32602() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        // NewSessionRequest requires `cwd`; this params object omits it. The
        // initialize handshake runs first so the failure is the params, not
        // the initialization gate.
        try await pushInitialize(transport)
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":12,"method":"session/new","params":{}}"#)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        XCTAssertEqual(response.id, .number(12))
        XCTAssertEqual(response.error?.code, -32602)

        await transport.finish()
        _ = await startTask.result
    }

    /// Session work before a successful initialize handshake is refused
    /// locally with -32002 and never reaches the delegate.
    func testSessionNewBeforeInitializeAnswers32002() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":20,"method":"session/new","params":{"cwd":"/tmp"}}"#,
        )

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        let events = await delegate.recordedEvents()

        XCTAssertEqual(response.id, .number(20))
        XCTAssertEqual(response.error?.code, -32002)
        XCTAssertTrue(events.isEmpty, "the delegate must not run before initialize")

        await transport.finish()
        _ = await startTask.result
    }

    /// A second initialize after the handshake completed is refused instead of
    /// renegotiating capabilities concurrently.
    func testDuplicateInitializeAfterHandshakeAnswers32600() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport, id: 30)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":31,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}"#,
        )

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        XCTAssertEqual(response.id, .number(31))
        XCTAssertEqual(response.error?.code, -32600)

        await transport.finish()
        _ = await startTask.result
    }

    /// A peer reusing an in-flight request id gets an explicit -32600 for the
    /// duplicate instead of having both handlers race for one response.
    func testDuplicateInflightRequestIDIsRefused() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport, id: 40)

        // Park the first request inside the delegate so the id is guaranteed
        // to still be in flight when the duplicate arrives.
        await delegate.suspendNextPromptTurn()

        let prompt = JSONRPCRequest(
            id: .number(41),
            method: "session/prompt",
            params: AnyCodable(["sessionId": "session-1", "prompt": [[
                "type": "text",
                "text": "hi",
            ]]] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(prompt))
        await delegate.waitUntilPromptStarted()

        let duplicate = JSONRPCRequest(
            id: .number(41),
            method: "session/prompt",
            params: AnyCodable(["sessionId": "session-1", "prompt": [[
                "type": "text",
                "text": "hi",
            ]]] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(duplicate))

        let refusalData = try await transport.nextSentFrame()
        let refusal = try JSONDecoder().decode(JSONRPCResponse.self, from: refusalData)
        XCTAssertEqual(refusal.id, .number(41))
        XCTAssertEqual(refusal.error?.code, -32600)

        // Releasing the original turn answers it normally.
        await delegate.releasePromptTurn(with: SessionPromptResponse(stopReason: .cancelled))
        let resultData = try await transport.nextSentFrame()
        let resultResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: resultData)
        XCTAssertEqual(resultResponse.id, .number(41))
        XCTAssertNil(resultResponse.error)
        let resultPayload = try JSONEncoder().encode(XCTUnwrap(resultResponse.result))
        let promptResponse = try JSONDecoder().decode(SessionPromptResponse.self, from: resultPayload)
        XCTAssertEqual(promptResponse.stopReason, .cancelled)

        await transport.finish()
        _ = await startTask.result
    }

    func testInvalidEnvelopeAnswers32600WithNullID() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        // Valid JSON object, invalid JSON-RPC envelope (wrong version). The id
        // is recoverable, so the -32600 response echoes it instead of null.
        try await transport.pushJSON(#"{"jsonrpc":"1.0","id":7,"method":"session/prompt","params":{}}"#)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        XCTAssertEqual(response.id, .number(7))
        XCTAssertEqual(response.error?.code, -32600)

        await transport.finish()
        _ = await startTask.result
    }

    func testCancelRequestNotificationRoutesToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        let notification = JSONRPCNotification(
            method: "$/cancel_request",
            params: AnyCodable(["requestId": 99]),
        )
        let notificationData = try JSONEncoder().encode(notification)
        try await transport.pushFrame(notificationData)

        try await Task.sleep(nanoseconds: 100_000_000)
        let events = await delegate.recordedEvents()

        XCTAssertEqual(events, ["cancel-request:99"])

        await transport.finish()
        _ = await startTask.result
    }

    func testAgentProcessesCancelWhilePromptSuspended() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        // Suspend the prompt inside the delegate. The initialize handshake
        // runs first: session/prompt is refused before it without one.
        try await pushInitialize(transport)
        await delegate.suspendNextPromptTurn()

        let prompt = JSONRPCRequest(
            id: .number(20),
            method: "session/prompt",
            params: AnyCodable(["sessionId": "session-1", "prompt": [[
                "type": "text",
                "text": "hi",
            ]]] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(prompt))
        await delegate.waitUntilPromptStarted()

        // While the prompt handler is suspended, a cancel must still be processed.
        let cancel = JSONRPCNotification(
            method: "session/cancel",
            params: AnyCodable(["sessionId": "session-1"]),
        )
        try await transport.pushFrame(JSONEncoder().encode(cancel))

        await delegate.waitUntilCancelRecorded()

        // Release the prompt turn; the agent maps the cancelled prompt to a
        // `.cancelled` response for the original request id.
        await delegate.releasePromptTurn(with: SessionPromptResponse(stopReason: .cancelled))

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        XCTAssertEqual(response.id, .number(20))
        let resultData = try JSONEncoder().encode(XCTUnwrap(response.result))
        let promptResponse = try JSONDecoder().decode(SessionPromptResponse.self, from: resultData)
        XCTAssertEqual(promptResponse.stopReason, .cancelled)

        await transport.finish()
        _ = await startTask.result
    }

    func testDraftAgentRequestsRouteToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        // The handshake authorizes session, nes, and mcp extension work.
        try await pushInitialize(transport)

        let forkRequest = JSONRPCRequest(
            id: .number(6),
            method: "session/fork",
            params: AnyCodable([
                "sessionId": "session-123",
                "cwd": "/tmp/fork",
                "additionalDirectories": ["/tmp/shared"],
            ] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(forkRequest))

        let forkResponseData = try await transport.nextSentFrame()
        let forkResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: forkResponseData)
        let forkResultData = try JSONEncoder().encode(XCTUnwrap(forkResponse.result))
        let forkResult = try JSONDecoder().decode(ForkSessionResponse.self, from: forkResultData)

        XCTAssertEqual(forkResponse.id, .number(6))
        XCTAssertNil(forkResponse.error)
        XCTAssertEqual(forkResult.sessionId.value, "session-forked")

        let providerRequest = JSONRPCRequest(
            id: .number(7),
            method: "providers/list",
            params: AnyCodable([String: String]()),
        )
        try await transport.pushFrame(JSONEncoder().encode(providerRequest))

        let providerResponseData = try await transport.nextSentFrame()
        let providerResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: providerResponseData)
        let providerResultData = try JSONEncoder().encode(XCTUnwrap(providerResponse.result))
        let providerResult = try JSONDecoder().decode(ListProvidersResponse.self, from: providerResultData)

        XCTAssertEqual(providerResult.providers.first?.providerId.value, "anthropic")

        let nesRequest = JSONRPCRequest(
            id: .number(8),
            method: "nes/suggest",
            params: AnyCodable([
                "sessionId": "nes-1",
                "uri": "file:///tmp/main.swift",
                "version": 1,
                "position": ["line": 0, "character": 0],
                "triggerKind": "manual",
            ] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(nesRequest))

        let nesResponseData = try await transport.nextSentFrame()
        let nesResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: nesResponseData)
        let nesResultData = try JSONEncoder().encode(XCTUnwrap(nesResponse.result))
        let nesResult = try JSONDecoder().decode(SuggestNesResponse.self, from: nesResultData)

        XCTAssertEqual(nesResult.suggestions.first?.id, "sug-1")

        let mcpRequest = JSONRPCRequest(
            id: .number(9),
            method: "mcp/message",
            params: AnyCodable([
                "connectionId": "conn-1",
                "method": "tools/list",
            ]),
        )
        try await transport.pushFrame(JSONEncoder().encode(mcpRequest))

        let mcpResponseData = try await transport.nextSentFrame()
        let mcpResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: mcpResponseData)
        let mcpResult = try XCTUnwrap(mcpResponse.result?.value as? [String: Any])

        XCTAssertEqual(mcpResult["ok"] as? Bool, true)

        let events = await delegate.recordedEvents()
        XCTAssertTrue(events.contains("fork:session-123:/tmp/fork:/tmp/shared"))
        XCTAssertTrue(events.contains("providers-list"))
        XCTAssertTrue(events.contains("nes-suggest:nes-1:manual"))
        XCTAssertTrue(events.contains("mcp-message:conn-1:tools/list"))

        await transport.finish()
        _ = await startTask.result
    }

    func testDraftAgentNotificationsRouteToDelegate() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await pushInitialize(transport)

        let reject = JSONRPCNotification(
            method: "nes/reject",
            params: AnyCodable([
                "sessionId": "nes-1",
                "id": "sug-1",
                "reason": "ignored",
            ]),
        )
        try await transport.pushFrame(JSONEncoder().encode(reject))

        let document = JSONRPCNotification(
            method: "document/didFocus",
            params: AnyCodable([
                "sessionId": "nes-1",
                "uri": "file:///tmp/main.swift",
                "version": 2,
                "position": ["line": 1, "character": 2],
                "visibleRange": [
                    "start": ["line": 0, "character": 0],
                    "end": ["line": 20, "character": 0],
                ],
            ] as [String: any Sendable]),
        )
        try await transport.pushFrame(JSONEncoder().encode(document))

        let mcp = JSONRPCNotification(
            method: "mcp/message",
            params: AnyCodable([
                "connectionId": "conn-1",
                "method": "notifications/tools/list_changed",
            ]),
        )
        try await transport.pushFrame(JSONEncoder().encode(mcp))

        try await Task.sleep(nanoseconds: 100_000_000)
        let events = await delegate.recordedEvents()

        XCTAssertTrue(events.contains("nes-reject:nes-1:sug-1:ignored"))
        XCTAssertTrue(events.contains("document-focus:nes-1:file:///tmp/main.swift"))
        XCTAssertTrue(events.contains("mcp-notification:conn-1:notifications/tools/list_changed"))

        await transport.finish()
        _ = await startTask.result
    }

    func testAgentCanInitiateClientDraftRequests() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)

        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        let connectTask = Task {
            try await agent.connectMcp(serverId: "server-1")
        }

        let connectRequestData = try await transport.nextSentFrame()
        let connectRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: connectRequestData)
        XCTAssertEqual(connectRequest.method, "mcp/connect")

        try await transport.pushFrame(JSONEncoder().encode(JSONRPCResponse(
            id: connectRequest.id,
            result: AnyCodable(["connectionId": "conn-1"]),
            error: nil,
        )))

        let connectResponse = try await connectTask.value
        XCTAssertEqual(connectResponse.connectionId.value, "conn-1")

        let elicitationTask = Task {
            try await agent.createElicitation(CreateElicitationRequest(
                mode: "form",
                message: "Need input",
                requestId: .number(99),
                requestedSchema: ElicitationSchema(),
            ))
        }

        let elicitationRequestData = try await transport.nextSentFrame()
        let elicitationRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: elicitationRequestData)
        XCTAssertEqual(elicitationRequest.method, "elicitation/create")

        try await transport.pushFrame(JSONEncoder().encode(JSONRPCResponse(
            id: elicitationRequest.id,
            result: AnyCodable(["action": "accept", "content": ["value": "ok"]] as [String: any Sendable]),
            error: nil,
        )))

        let elicitationResponse = try await elicitationTask.value
        XCTAssertEqual(elicitationResponse.action, "accept")
        XCTAssertEqual(elicitationResponse.content?["value"]?.value as? String, "ok")

        await transport.finish()
        _ = await startTask.result
    }

    func testClientRequestRouterRoutesDraftMethods() async throws {
        let router = ACPRequestRouter()
        let delegate = RecordingClientDelegate()
        router.setDelegate(delegate)

        let connect = JSONRPCRequest(
            id: .number(1),
            method: "mcp/connect",
            params: AnyCodable(["serverId": "server-1"]),
        )
        let connectResult = try await router.routeRequest(connect)
        let connectData = try JSONEncoder().encode(connectResult)
        let connectResponse = try JSONDecoder().decode(ConnectMcpResponse.self, from: connectData)

        XCTAssertEqual(connectResponse.connectionId.value, "conn-1")

        let elicitation = JSONRPCRequest(
            id: .number(2),
            method: "elicitation/create",
            params: AnyCodable([
                "mode": "url",
                "message": "Authorize",
                "requestId": 12,
                "elicitationId": "elicit-1",
                "url": "https://example.com",
            ] as [String: any Sendable]),
        )
        let elicitationResult = try await router.routeRequest(elicitation)
        let elicitationData = try JSONEncoder().encode(elicitationResult)
        let elicitationResponse = try JSONDecoder().decode(CreateElicitationResponse.self, from: elicitationData)

        XCTAssertEqual(elicitationResponse.action, "decline")

        try await router.routeNotification(JSONRPCNotification(
            method: "mcp/message",
            params: AnyCodable(["connectionId": "conn-1", "method": "notifications/progress"]),
        ))
        try await router.routeNotification(JSONRPCNotification(
            method: "elicitation/complete",
            params: AnyCodable(["elicitationId": "elicit-1"]),
        ))

        let events = await delegate.events
        XCTAssertEqual(events, [
            "mcp-connect:server-1",
            "elicitation-create:url",
            "mcp-notification:conn-1:notifications/progress",
            "elicitation-complete:elicit-1",
        ])
    }

    // MARK: - Generic permission and session-config routes (VOY-700)

    /// session/request_permission round-trips through the agent's pending
    /// request table with concurrent requests correlated by id.
    /// - 검증 내용: 두 동시 permission 요청이 교차 순서 응답에서 정확히 상관되는지 확인합니다.
    /// - 사전 조건: ScriptedTransport로 붙은 agent와 pending table이 제공됩니다.
    /// - 기대 결과: 각 await는 자신의 id 응답으로 정산되고 wire method는 session/request_permission입니다.
    func testRequestPermissionRoundTripsThroughAgentPendingTable() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        let firstTask = Task {
            try await agent.requestPermission(RequestPermissionRequest(
                options: [PermissionOption(kind: "allow_once", name: "Allow", optionId: "opt-allow")],
                sessionId: SessionId("perm-session"),
                toolCall: ToolCallUpdate(toolCallId: "tool-1", title: "Read file"),
            ))
        }
        let secondTask = Task {
            try await agent.requestPermission(RequestPermissionRequest(
                options: [PermissionOption(kind: "reject_once", name: "Deny", optionId: "opt-deny")],
                sessionId: SessionId("perm-session"),
                toolCall: ToolCallUpdate(toolCallId: "tool-2", title: "Write file"),
            ))
        }

        let firstRequestData = try await transport.nextSentFrame()
        let firstRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: firstRequestData)
        XCTAssertEqual(firstRequest.method, "session/request_permission")
        let secondRequestData = try await transport.nextSentFrame()
        let secondRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: secondRequestData)
        XCTAssertEqual(secondRequest.method, "session/request_permission")
        XCTAssertNotEqual(firstRequest.id, secondRequest.id)

        // 어느 task가 먼저 id를 배정받았는지와 무관하게 payload로 frame을 식별하고,
        // 응답은 요청과 반대 순서로 반환해 pending table의 id 상관을 강제한다.
        func toolCallId(of request: JSONRPCRequest) -> String? {
            guard let params = request.params?.value as? [String: Any],
                  let toolCall = params["toolCall"] as? [String: Any] else { return nil }
            return toolCall["toolCallId"] as? String
        }
        func outcomeFrame(_ request: JSONRPCRequest, optionId: String) -> JSONRPCResponse {
            JSONRPCResponse(
                id: request.id,
                result: AnyCodable(["outcome": ["outcome": "selected", "optionId": optionId]]),
                error: nil,
            )
        }
        guard let allowRequest = [firstRequest, secondRequest].first(where: { toolCallId(of: $0) == "tool-1" }),
              let denyRequest = [firstRequest, secondRequest].first(where: { toolCallId(of: $0) == "tool-2" })
        else {
            XCTFail("both permission requests must carry their tool call id")
            return
        }
        try await transport.pushFrame(JSONEncoder().encode(outcomeFrame(denyRequest, optionId: "opt-deny")))
        try await transport.pushFrame(JSONEncoder().encode(outcomeFrame(allowRequest, optionId: "opt-allow")))

        let first = try await firstTask.value
        let second = try await secondTask.value
        XCTAssertEqual(first.outcome.optionId, "opt-allow")
        XCTAssertEqual(second.outcome.optionId, "opt-deny")

        await transport.finish()
        _ = await startTask.result
    }

    /// A pending permission request settles exactly once when the agent's
    /// request lifecycle ends, and cancellation notifications keep routing
    /// while a permission is outstanding.
    /// - 검증 내용: 진행 중 permission 위에 $/cancel_request 라우팅과 close 정산을 확인합니다.
    /// - 사전 조건: 응답 없는 permission 요청이 pending table에 유지됩니다.
    /// - 기대 결과: cancel 요청은 delegate에 기록되고 close는 pending을 connectionClosed로 한 번 정산합니다.
    func testRequestPermissionCancellationAndCloseSettlePendingRequest() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)
        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        let pending = Task {
            try await agent.requestPermission(RequestPermissionRequest(
                options: [PermissionOption(kind: "allow_once", name: "Allow", optionId: "opt-allow")],
                sessionId: SessionId("perm-session"),
                toolCall: ToolCallUpdate(toolCallId: "tool-1", title: "Read file"),
            ))
        }
        _ = try await transport.nextSentFrame()

        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","method":"$/cancel_request","params":{"requestId":1}}"#,
        )
        await delegate.waitUntilCancelRequestRecorded()

        await agent.close()
        do {
            _ = try await pending.value
            XCTFail("a pending permission request must not survive close")
        } catch {
            guard case ClientError.connectionClosed = error else {
                return XCTFail("expected connectionClosed, got \(error)")
            }
        }

        await transport.finish()
        _ = await startTask.result
    }

    /// session/set_config_option waits for the handshake and routes to the
    /// typed delegate method once initialized.
    /// - 검증 내용: 초기화 전 -32002, 초기화 후 delegate 왕복과 응답 인코딩을 확인합니다.
    /// - 사전 조건: config recorder delegate가 붙은 agent가 제공됩니다.
    /// - 기대 결과: 초기화 전에는 Not initialized, 이후에는 delegate 응답이 wire로 돌아갑니다.
    func testSetConfigOptionRequiresInitializeAndReturnsDelegateResponse() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = RecordingAgentDelegate()
        await agent.setDelegate(delegate)
        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }

        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":20,"method":"session/set_config_option","params":{"sessionId":"s","configId":"model","value":"claude-opus"}}"#,
        )
        let beforeData = try await transport.nextSentFrame()
        let before = try JSONDecoder().decode(JSONRPCResponse.self, from: beforeData)
        XCTAssertEqual(before.id, .number(20))
        XCTAssertEqual(before.error?.code, -32002)

        try await pushInitialize(transport, id: 21)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":22,"method":"session/set_config_option","params":{"sessionId":"s","configId":"model","value":"claude-opus"}}"#,
        )
        let afterData = try await transport.nextSentFrame()
        let after = try JSONDecoder().decode(JSONRPCResponse.self, from: afterData)
        XCTAssertEqual(after.id, .number(22))
        XCTAssertNil(after.error)
        let events = await delegate.recordedEvents()
        print("DEBUG-EVENTS: \(events)")
        print("DEBUG-ERROR: \(String(describing: after.error))")
        XCTAssertTrue(events.contains("config:model"))

        await transport.finish()
        _ = await startTask.result
    }

    /// With the default delegate the typed route answers an explicit
    /// unsupported error and does not leak the request into the custom stream.
    /// - 검증 내용: 기본 delegate에서 -32601 응답과 requests stream 비사용을 확인합니다.
    /// - 사전 조건: config 기본 구현을 유지하는 delegate가 붙어 있습니다.
    /// - 기대 결과: -32601로 응답되고 requests stream은 이후 알려진 unknown method만 운반합니다.
    func testSetConfigOptionDefaultDelegateRemainsExplicitlyUnsupported() async throws {
        let transport = ScriptedTransport()
        let agent = Agent(transport: transport)
        let delegate = EchoVersionAgentDelegate()
        await agent.setDelegate(delegate)
        let startTask = Task {
            await agent.start()
        }
        defer {
            startTask.cancel()
        }
        let customRequests = Task {
            await agent.requests.first(where: { _ in true })
        }

        try await pushInitialize(transport, id: 30)
        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":31,"method":"session/set_config_option","params":{"sessionId":"s","configId":"model","value":"claude-opus"}}"#,
        )
        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
        XCTAssertEqual(response.id, .number(31))
        XCTAssertEqual(response.error?.code, -32601)

        // 요청 처리는 순서대로 진행된다. 뒤이은 미지정 method가 custom stream에
        // 도착하면, 그보다 앞선 config 요청이 stream으로 새지 않았음이 확정된다.
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":32,"method":"totally/unknown","params":{}}"#)
        _ = try await transport.nextSentFrame()
        let firstCustom = try await customRequests.value
        XCTAssertEqual(firstCustom?.method, "totally/unknown")

        await transport.finish()
        _ = await startTask.result
    }
}

private actor EchoVersionAgentDelegate: AgentDelegate {
    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse {
        InitializeResponse(
            protocolVersion: request.protocolVersion,
            agentCapabilities: AgentCapabilities(),
            _meta: ["marker": AnyCodable("preserved")],
        )
    }

    func handleNewSession(_: NewSessionRequest) async throws -> NewSessionResponse {
        throw ClientError.invalidResponse
    }

    func handlePrompt(_: SessionPromptRequest) async throws -> SessionPromptResponse {
        throw ClientError.invalidResponse
    }
}

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

        // NewSessionRequest requires `cwd`; this params object omits it.
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":12,"method":"session/new","params":{}}"#)

        let responseData = try await transport.nextSentFrame()
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)

        XCTAssertEqual(response.id, .number(12))
        XCTAssertEqual(response.error?.code, -32602)

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

        // Suspend the prompt inside the delegate.
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

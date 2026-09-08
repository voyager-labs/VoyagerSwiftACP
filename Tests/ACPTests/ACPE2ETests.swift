@testable import ACP
import XCTest

/// E2E tests using a mock agent script that responds to JSON-RPC messages
final class ACPE2ETests: XCTestCase {
    var mockAgentPath: String!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mockAgentPath = tempDir.appendingPathComponent("mock-agent.sh").path
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockAgent(script: String) throws {
        let fullScript = """
        #!/bin/bash
        \(script)
        """
        try fullScript.write(toFile: mockAgentPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockAgentPath)
    }

    private func makeCapabilities() -> ClientCapabilities {
        ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true,
        )
    }

    // MARK: - E2E Tests

    func testClientLaunchAndTerminate() async throws {
        try createMockAgent(script: """
        # Simple agent that exits on signal
        trap 'exit 0' TERM
        sleep 10
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        // Should be able to terminate cleanly
        await client.terminate()
    }

    func testInitializeRequest() async throws {
        try createMockAgent(script: """
        # Read request and send response
        read -r line
        # Extract id from request
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"MockAgent","version":"1.0.0"}}}'
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let response = try await client.initialize(
            protocolVersion: 1,
            capabilities: makeCapabilities(),
            timeout: 5.0,
        )

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "MockAgent")
        XCTAssertEqual(response.agentInfo?.version, "1.0.0")

        await client.terminate()
    }

    func testNewSessionRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"MockAgent","version":"1.0.0"}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let session = try await client.newSession(
            workingDirectory: "/tmp",
            timeout: 5.0,
        )

        XCTAssertEqual(session.sessionId.value, "session-123")

        await client.terminate()
    }

    func testListSessionsRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"list":{}}}}}'
            elif [ "$method" = "session/list" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessions":[{"sessionId":"session-123","cwd":"/tmp/project","title":"Investigate latest ACP changes","updatedAt":"2026-03-09T12:00:00Z"}],"nextCursor":"cursor-2"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let response = try await client.listSessions(cwd: "/tmp/project", timeout: 5.0)

        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions.first?.sessionId.value, "session-123")
        XCTAssertEqual(response.sessions.first?.title, "Investigate latest ACP changes")
        XCTAssertEqual(response.nextCursor, "cursor-2")

        await client.terminate()
    }

    func testCloseSessionRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            sessionId=$(echo "$line" | grep -o '"sessionId":"[^"]*"' | sed 's/"sessionId":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"close":{}}}}}'
            elif [ "$method" = "session/close" ]; then
                if [ "$sessionId" = "session-123" ]; then
                    echo '{"jsonrpc":"2.0","id":'$id',"result":{}}'
                else
                    echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32602,"message":"Unexpected sessionId"}}'
                fi
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let response = try await client.closeSession(sessionId: SessionId("session-123"))
        XCTAssertNotNil(response)

        await client.terminate()
    }

    func testLoadSessionRequestUsesStableSchemaShape() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            sessionId=$(echo "$line" | grep -o '"sessionId":"[^"]*"' | sed 's/"sessionId":"\\([^"]*\\)"/\\1/')
            cwd=$(echo "$line" | grep -o '"cwd":"[^"]*"' | sed 's/"cwd":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true}}}'
            elif [ "$method" = "session/load" ]; then
                if echo "$line" | grep -q '"mcpServers":\\[\\]' && [ "$sessionId" = "session-123" ] && [ "$cwd" = "/tmp/project" ]; then
                    echo '{"jsonrpc":"2.0","id":'$id',"result":{"modes":{"currentModeId":"chat","availableModes":[{"id":"chat","name":"Chat"}]}}}'
                else
                    echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32602,"message":"Unexpected load payload"}}'
                fi
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let response = try await client.loadSession(
            sessionId: SessionId("session-123"),
            cwd: "/tmp/project",
            mcpServers: [],
        )

        XCTAssertNil(response.sessionId)
        XCTAssertEqual(response.modes?.currentModeId, "chat")
        XCTAssertEqual(response.modes?.availableModes.first?.id, "chat")

        await client.terminate()
    }

    func testStableResumeDeleteAndLogoutRequests() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            sessionId=$(echo "$line" | grep -o '"sessionId":"[^"]*"' | sed 's/"sessionId":"\\([^"]*\\)"/\\1/')
            cwd=$(echo "$line" | grep -o '"cwd":"[^"]*"' | sed 's/"cwd":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"auth":{"logout":{}},"sessionCapabilities":{"additionalDirectories":{},"resume":{},"delete":{}}}}}'
            elif [ "$method" = "session/resume" ]; then
                if echo "$line" | grep -q '"additionalDirectories":\\["/tmp/shared"\\]' && [ "$sessionId" = "session-123" ] && [ "$cwd" = "/tmp/project" ]; then
                    echo '{"jsonrpc":"2.0","id":'$id',"result":{"modes":{"currentModeId":"chat","availableModes":[{"id":"chat","name":"Chat"}]}}}'
                else
                    echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32602,"message":"Unexpected resume payload"}}'
                fi
            elif [ "$method" = "session/delete" ]; then
                if [ "$sessionId" = "session-123" ]; then
                    echo '{"jsonrpc":"2.0","id":'$id',"result":{}}'
                else
                    echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32602,"message":"Unexpected delete payload"}}'
                fi
            elif [ "$method" = "logout" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let resume = try await client.resumeSession(
            sessionId: SessionId("session-123"),
            cwd: "/tmp/project",
            additionalDirectories: ["/tmp/shared"],
        )
        XCTAssertEqual(resume.modes?.currentModeId, "chat")

        let deleteResponse = try await client.deleteSession(sessionId: SessionId("session-123"))
        XCTAssertNotNil(deleteResponse)

        let logoutResponse = try await client.logout()
        XCTAssertNotNil(logoutResponse)

        await client.terminate()
    }

    func testNotificationStream() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
                # Known variant for a registered session is delivered as-is.
                echo '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-123","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello from agent"}}}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let notificationStream = await client.notifications

        // Start listening for notifications before sending request
        let notificationTask = Task {
            var receivedNotification = false
            for await notification in notificationStream where notification.method == "session/update" {
                receivedNotification = true
                break
            }
            return receivedNotification
        }

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
        // Register the session so the agent update targets a tracked session.
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)
        XCTAssertEqual(session.sessionId.value, "session-123")

        // Give time for notification to arrive
        try await Task.sleep(nanoseconds: 500_000_000)

        await client.terminate()

        let result = await notificationTask.value
        XCTAssertTrue(result, "Should have received session/update notification")
    }

    func testRequestTimeout() async throws {
        try createMockAgent(script: """
        # Never respond - keep process alive so timeout is the dominant failure mode.
        read -r line
        sleep 5
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 0.5)
            XCTFail("Should have thrown timeout error")
        } catch let error as ClientError {
            switch error {
            case .requestTimeout:
                break // Expected
            default:
                XCTFail("Expected requestTimeout, got: \(error)")
            }
        }

        await client.terminate()
    }

    /// Replaced recovery fixture `testInitializeWithNonJSONPrefixSameLine`.
    /// Strict ACP stdio framing: a non-JSON stdout line is a typed malformed
    /// frame failure, not something to resynchronize past.
    func testNonJSONStdoutPrefixFailsConnection() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                printf 'NONJSON_PREFIX\n'
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
                break
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(
                protocolVersion: 1,
                capabilities: makeCapabilities(),
                timeout: 5.0,
            )
            XCTFail("expected malformed frame failure")
        } catch let error as ClientError {
            guard case .transportFailure(.malformedFrame) = error else {
                return XCTFail("expected transportFailure(.malformedFrame), got \(error)")
            }
        }

        let evidence = await client.shutdown()
        guard case .failure(.malformedFrame) = evidence.reason else {
            return XCTFail("expected malformed frame evidence, got \(evidence.reason)")
        }
    }

    /// Replaced recovery fixture `testInitializeRecoversAfterMalformedJSONLine`.
    /// Strict ACP stdio framing: a truncated JSON line terminates the connection
    /// with a typed failure instead of being discarded.
    func testMalformedJSONLineFailsConnection() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":'
                break
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(
                protocolVersion: 1,
                capabilities: makeCapabilities(),
                timeout: 5.0,
            )
            XCTFail("expected malformed frame failure")
        } catch let error as ClientError {
            guard case .transportFailure(.malformedFrame) = error else {
                return XCTFail("expected transportFailure(.malformedFrame), got \(error)")
            }
        }

        await client.terminate()
    }

    func testProcessTerminationError() async throws {
        try createMockAgent(script: """
        # Exit immediately
        exit 1
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        // Wait for process to exit
        try await Task.sleep(nanoseconds: 200_000_000)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 2.0)
            XCTFail("Should have thrown error")
        } catch let error as ClientError {
            switch error {
            case .processNotRunning, .processFailed:
                break // Expected
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }

        await client.terminate()
    }

    func testDebugStream() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            break
        done
        """)

        let client = Client()
        await client.enableDebugStream()

        try await client.launch(agentPath: mockAgentPath)

        let debugTask = Task {
            var collected: [DebugMessage] = []
            guard let stream = await client.debugMessages else { return collected }
            for await message in stream {
                collected.append(message)
                if collected.count >= 2 { break }
            }
            return collected
        }

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        // Give time for debug messages to be collected
        try await Task.sleep(nanoseconds: 500_000_000)

        await client.terminate()

        let debugMessages = await debugTask.value

        XCTAssertGreaterThanOrEqual(debugMessages.count, 1)

        // Should have at least one outgoing message (the request)
        let outgoing = debugMessages.filter { $0.direction == .outgoing }
        XCTAssertGreaterThanOrEqual(outgoing.count, 1)
    }

    func testMultipleSequentialRequests() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-'$id'"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        // Create multiple sessions sequentially
        let session1 = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)
        let session2 = try await client.newSession(workingDirectory: "/var", timeout: 5.0)
        let session3 = try await client.newSession(workingDirectory: "/home", timeout: 5.0)

        XCTAssertNotEqual(session1.sessionId.value, session2.sessionId.value)
        XCTAssertNotEqual(session2.sessionId.value, session3.sessionId.value)

        await client.terminate()
    }

    func testAgentErrorResponse() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32600,"message":"Invalid request"}}'
            break
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            XCTFail("Should have thrown agent error")
        } catch let error as ClientError {
            if case let .agentError(rpcError) = error {
                XCTAssertEqual(rpcError.code, -32600)
                XCTAssertEqual(rpcError.message, "Invalid request")
            } else {
                XCTFail("Expected agent error, got: \(error)")
            }
        }

        await client.terminate()
    }

    func testSendPromptRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
            elif [ "$method" = "session/prompt" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)

        let response = try await client.sendPrompt(
            sessionId: session.sessionId,
            content: [.text(TextContent(text: "Hello, agent!"))],
        )

        XCTAssertEqual(response.stopReason, .endTurn)

        await client.terminate()
    }

    func testPendingPermissionRequestDoesNotBlockPromptResponse() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
            elif [ "$method" = "session/prompt" ]; then
                printf '%s\n%s\n' \
                    '{"jsonrpc":"2.0","id":900,"method":"session/request_permission","params":{"sessionId":"session-123","options":[{"kind":"allow_once","name":"Allow once","optionId":"allow"}],"toolCall":{"toolCallId":"tc-1","status":"pending","title":"Run command"}}}' \
                    '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}'
            fi
        done
        """)

        let delegate = BlockingPermissionDelegate()
        let client = Client()
        await client.setDelegate(delegate)
        try await client.launch(agentPath: mockAgentPath)
        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)

        let promptTask = Task {
            try await client.sendPrompt(
                sessionId: session.sessionId,
                content: [.text(TextContent(text: "Continue"))],
            )
        }
        await delegate.waitUntilRequested()

        let promptFinished = expectation(description: "prompt response is handled while permission is pending")
        let completionTask = Task {
            let response = try await promptTask.value
            promptFinished.fulfill()
            return response
        }

        await fulfillment(of: [promptFinished], timeout: 0.5)
        await delegate.resolvePermission()

        let response = try await completionTask.value
        XCTAssertEqual(response.stopReason, .endTurn)
        await client.terminate()
    }

    func testClientForwardsCompleteStderrLinesAcrossChunks() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        printf 'first' >&2
        sleep 0.05
        printf ' line\nsecond line\n' >&2
        sleep 10
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        guard let stderrLines = await client.stderrLines() else {
            XCTFail("Expected stderr stream after launch")
            await client.terminate()
            return
        }

        let linesTask = Task {
            var lines: [String] = []
            for await line in stderrLines {
                lines.append(line)
                if lines.count == 2 { break }
            }
            return lines
        }

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5)
        let lines = await linesTask.value
        XCTAssertEqual(lines, ["first line", "second line"])
        await client.terminate()
    }

    func testClientExposesProcessIdentifiersOnlyWhileRunning() async throws {
        try createMockAgent(script: """
        trap 'exit 0' TERM
        sleep 10
        """)

        let client = Client()
        let processIdentifierBeforeLaunch = await client.processIdentifier()
        let processGroupIdentifierBeforeLaunch = await client.processGroupIdentifier()
        XCTAssertNil(processIdentifierBeforeLaunch)
        XCTAssertNil(processGroupIdentifierBeforeLaunch)

        try await client.launch(agentPath: mockAgentPath)

        let processIdentifier = await client.processIdentifier()
        let processGroupIdentifier = await client.processGroupIdentifier()
        XCTAssertNotNil(processIdentifier)
        XCTAssertGreaterThan(processIdentifier ?? 0, 0)
        if let processGroupIdentifier {
            XCTAssertEqual(processGroupIdentifier, processIdentifier)
        }

        await client.terminate()
        let processIdentifierAfterTerminate = await client.processIdentifier()
        let processGroupIdentifierAfterTerminate = await client.processGroupIdentifier()
        XCTAssertNil(processIdentifierAfterTerminate)
        XCTAssertNil(processGroupIdentifierAfterTerminate)
    }

    func testStdioTransportPreservesFragmentedMessageOrder() async throws {
        try createMockAgent(script: """
        i=0
        while [ $i -lt 2000 ]; do
            printf '{"jsonrpc":"2.0","method":"sequence","params":{"value":%d' "$i"
            printf '}}\n'
            i=$((i + 1))
        done
        """)

        let transport = StdioTransport()
        let messages = transport.messages
        let collected = expectation(description: "all fragmented messages are collected")
        let valuesTask = Task {
            var values: [Int] = []
            for await message in messages {
                let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
                let params = object?["params"] as? [String: Any]
                if let value = params?["value"] as? Int {
                    values.append(value)
                }
            }
            collected.fulfill()
            return values
        }

        try await transport.launch(executablePath: mockAgentPath)
        await fulfillment(of: [collected], timeout: 5.0)

        let values = try await valuesTask.value
        XCTAssertEqual(values, Array(0 ..< 2000))
        await transport.close()
    }
}

private actor BlockingPermissionDelegate: ClientDelegate {
    private var requestReceived = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var permissionContinuation: CheckedContinuation<RequestPermissionResponse, Never>?

    func waitUntilRequested() async {
        guard !requestReceived else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resolvePermission() {
        permissionContinuation?.resume(
            returning: RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow")),
        )
        permissionContinuation = nil
    }

    func handlePermissionRequest(request _: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        requestReceived = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            permissionContinuation = continuation
        }
    }

    func handleFileReadRequest(
        _: String,
        sessionId _: String,
        line _: Int?,
        limit _: Int?,
    ) async throws -> ReadTextFileResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleFileWriteRequest(
        _: String,
        content _: String,
        sessionId _: String,
    ) async throws -> WriteTextFileResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleTerminalCreate(
        command _: String,
        sessionId _: String,
        args _: [String]?,
        cwd _: String?,
        env _: [EnvVariable]?,
        outputByteLimit _: Int?,
    ) async throws -> CreateTerminalResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleTerminalOutput(terminalId _: TerminalId, sessionId _: String) async throws -> TerminalOutputResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleTerminalWaitForExit(terminalId _: TerminalId, sessionId _: String) async throws -> WaitForExitResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleTerminalKill(terminalId _: TerminalId, sessionId _: String) async throws -> KillTerminalResponse {
        throw ClientError.unknownMethod("unused test callback")
    }

    func handleTerminalRelease(terminalId _: TerminalId, sessionId _: String) async throws -> ReleaseTerminalResponse {
        throw ClientError.unknownMethod("unused test callback")
    }
}

// MARK: - Delegate Tests

final class ACPDelegateTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testFileSystemDelegateReadFile() async throws {
        // Create a test file
        let testFilePath = tempDir.appendingPathComponent("test.txt").path
        try "Hello, World!".write(toFile: testFilePath, atomically: true, encoding: .utf8)

        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(testFilePath, sessionId: "s1", line: nil, limit: nil)

        XCTAssertEqual(response.content, "Hello, World!")
    }

    func testFileSystemDelegateWriteFile() async throws {
        let testFilePath = tempDir.appendingPathComponent("output.txt").path

        let delegate = FileSystemDelegate()
        _ = try await delegate.handleFileWriteRequest(testFilePath, content: "Test content", sessionId: "s1")

        let writtenContent = try String(contentsOfFile: testFilePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, "Test content")
    }

    func testFileSystemDelegateReadWithLineOffset() async throws {
        let testFilePath = tempDir.appendingPathComponent("multiline.txt").path
        let content = (1 ... 10).map { "Line \($0)" }.joined(separator: "\n")
        try content.write(toFile: testFilePath, atomically: true, encoding: .utf8)

        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(testFilePath, sessionId: "s1", line: 5, limit: 2)

        // Should read lines 5-6 (0-indexed from line 5, limit 2)
        XCTAssertTrue(response.content.contains("Line 5") || response.content.contains("Line 6"))
    }

    func testFileSystemDelegateReadNonexistentFile() async throws {
        let delegate = FileSystemDelegate()

        do {
            _ = try await delegate.handleFileReadRequest(
                "/nonexistent/path/file.txt",
                sessionId: "s1",
                line: nil,
                limit: nil,
            )
            XCTFail("Should have thrown error for nonexistent file")
        } catch {
            // Expected
        }
    }
}

// MARK: - Integration Tests for Types

final class ACPTypeIntegrationTests: XCTestCase {
    func testFullJSONRPCMessageRoundTrip() throws {
        let request = JSONRPCRequest(
            id: .number(42),
            method: "session/prompt",
            params: AnyCodable([
                "sessionId": "session-123",
                "prompt": [
                    ["type": "text", "text": "Hello, agent!"],
                ],
            ] as [String: any Sendable]),
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(request)
        let decoded = try decoder.decode(JSONRPCRequest.self, from: data)

        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.method, request.method)
    }

    func testSessionUpdateNotificationRoundTrip() throws {
        let notification = SessionUpdateNotification(
            sessionId: SessionId("session-123"),
            update: .agentMessageChunk(.text(TextContent(text: "Hello!"))),
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(notification)
        let decoded = try decoder.decode(SessionUpdateNotification.self, from: data)

        XCTAssertEqual(decoded.sessionId.value, "session-123")
        XCTAssertEqual(decoded.update.sessionUpdateType, "agent_message_chunk")
    }

    func testToolCallUpdateRoundTrip() throws {
        let update = ToolCallUpdate(
            toolCallId: "tc-1",
            status: .completed,
            title: "Read File",
            kind: .read,
            content: [.content(.text(TextContent(text: "file contents")))],
            locations: [ToolLocation(path: "/tmp/file.txt", line: 10)],
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(update)
        let decoded = try decoder.decode(ToolCallUpdate.self, from: data)

        XCTAssertEqual(decoded.toolCallId, "tc-1")
        XCTAssertEqual(decoded.status, .completed)
        XCTAssertEqual(decoded.title, "Read File")
        XCTAssertEqual(decoded.kind, .read)
        XCTAssertEqual(decoded.locations?.first?.path, "/tmp/file.txt")
    }

    func testComplexSessionUpdateParsing() throws {
        let json = """
        {
            "sessionUpdate": "tool_call",
            "toolCallId": "call-abc-123",
            "title": "Searching for files",
            "kind": "search",
            "status": "in_progress",
            "content": [
                {"type": "content", "content": {"type": "text", "text": "Searching..."}}
            ],
            "locations": [
                {"path": "/project/src", "line": null}
            ]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.toolCallId, "call-abc-123")
        XCTAssertEqual(update.title, "Searching for files")
        XCTAssertEqual(update.kind, .search)
        XCTAssertEqual(update.status, .inProgress)
    }

    func testInitializeResponseDecoding() throws {
        let json = """
        {
            "protocolVersion": 1,
            "agentCapabilities": {
            },
            "agentInfo": {
                "name": "TestAgent",
                "version": "2.0.0",
                "title": "Test Agent"
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(InitializeResponse.self, from: data)

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "TestAgent")
        XCTAssertEqual(response.agentInfo?.version, "2.0.0")
    }

    func testNewSessionResponseDecoding() throws {
        let json = """
        {
            "sessionId": "session-456",
            "modes": {
                "currentModeId": "code",
                "availableModes": [
                    {"id": "code", "name": "Code Mode"},
                    {"id": "chat", "name": "Chat Mode"}
                ]
            },
            "models": {
                "currentModelId": "gpt-4",
                "availableModels": [
                    {"modelId": "gpt-4", "name": "GPT-4"},
                    {"modelId": "gpt-3.5", "name": "GPT-3.5"}
                ]
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try JSONDecoder().decode(NewSessionResponse.self, from: data)

        XCTAssertEqual(response.sessionId.value, "session-456")
        XCTAssertEqual(response.modes?.currentModeId, "code")
        XCTAssertEqual(response.modes?.availableModes.count, 2)
        XCTAssertEqual(response.models?.currentModelId, "gpt-4")
    }

    func testRequestPermissionRequestUsesToolCallUpdateShape() throws {
        let json = """
        {
            "sessionId": "session-123",
            "options": [
                {"kind": "allow_once", "name": "Allow once", "optionId": "opt-allow"},
                {"kind": "reject_once", "name": "Reject once", "optionId": "opt-deny"}
            ],
            "toolCall": {
                "toolCallId": "tc-123",
                "status": "pending",
                "title": "Run npm install",
                "rawInput": {"command": "npm install"}
            }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let request = try JSONDecoder().decode(RequestPermissionRequest.self, from: data)

        XCTAssertEqual(request.sessionId.value, "session-123")
        XCTAssertEqual(request.options.count, 2)
        XCTAssertEqual(request.toolCall.toolCallId, "tc-123")
        XCTAssertEqual(request.toolCall.status, .pending)
        XCTAssertEqual(request.toolCall.title, "Run npm install")
    }
}

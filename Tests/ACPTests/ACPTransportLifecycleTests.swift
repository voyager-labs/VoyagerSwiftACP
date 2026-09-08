//
//  ACPTransportLifecycleTests.swift
//  ACPTests
//
//  T7: direct-child lifecycle — startup failure, EOF, bounded shutdown, exit
//  evidence — exercised through the real stdio subprocess path.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPTransportLifecycleTests: XCTestCase {
    var tempDir: URL!
    var agentPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        agentPath = tempDir.appendingPathComponent("lifecycle-agent.sh").path
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    private func createAgent(script: String) throws {
        let fullScript = """
        #!/bin/bash
        \(script)
        """
        try fullScript.write(toFile: agentPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentPath)
    }

    private func makeCapabilities() -> ClientCapabilities {
        ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true,
        )
    }

    private func echoAgent() throws {
        try createAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-'$id'"}}'
            elif [ "$method" = "session/prompt" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}'
            fi
        done
        """)
    }

    private func initialize(_ client: Client) async throws {
        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5)
    }

    /// L01
    func testStartupFailureCleansPipes() async throws {
        try createAgent(script: "sleep 10")
        let client = Client()

        do {
            try await client.launch(agentPath: "/nonexistent/acp-agent-binary")
            XCTFail("expected startup failure")
        } catch {
            // expected typed failure
        }

        let pid = await client.processIdentifier()
        XCTAssertNil(pid)

        let evidence = await client.shutdown()
        guard case .failure(.startup) = evidence.reason else {
            return XCTFail("expected startup failure evidence, got \(evidence.reason)")
        }
        XCTAssertTrue(evidence.cleanupComplete)
    }

    /// L02
    func testStdinWriteFailureFailsPending() async throws {
        try createAgent(script: """
        exec 0<&-
        echo '{"ready":true}'
        sleep 10
        """)
        let transport = StdioTransport()
        try await transport.launch(executablePath: agentPath)
        var iterator = transport.messages.makeAsyncIterator()
        _ = await iterator.next()
        do {
            try await transport.send(Data("{}".utf8))
            XCTFail("expected broken pipe")
        } catch let error as ClientError {
            guard case .transportFailure(.write) = error else {
                return XCTFail("expected typed write failure, got \(error)")
            }
        }
        _ = await transport.shutdown()
    }

    /// L03
    func testStdoutEOFFailsPendingWhileProcessAlive() async throws {
        try createAgent(script: """
        read -r line
        exec 1>&-
        sleep 10
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)
        do {
            try await initialize(client)
            XCTFail("expected EOF failure while initialize is pending")
        } catch let error as ClientError {
            guard case .connectionClosed = error else {
                return XCTFail("expected connection closure, got \(error)")
            }
        }
        let evidence = await client.shutdown()
        XCTAssertEqual(evidence.reason, .stdoutEOF)
        XCTAssertTrue(evidence.cleanupComplete)
        let pid = await client.processIdentifier()
        XCTAssertNil(pid)
    }

    /// L04
    func testMalformedFrameTerminatesConnection() async throws {
        try createAgent(script: """
        read -r line
        echo 'THIS IS NOT JSON AT ALL'
        exec sleep 10
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)
        do {
            try await initialize(client)
            XCTFail("expected malformed frame failure")
        } catch let error as ClientError {
            guard case .transportFailure(.malformedFrame) = error else {
                return XCTFail("expected transportFailure(.malformedFrame), got \(error)")
            }
        }
        let evidence = await client.shutdown()
        guard case .failure(.malformedFrame) = evidence.reason else {
            return XCTFail("expected malformed-frame terminal evidence")
        }
        let state = await client.state
        XCTAssertEqual(state, .failed)
    }

    /// L05
    func testStderrIsDrainedAndDiscardedByDefault() async throws {
        try createAgent(script: """
        for i in $(seq 1 200); do
            echo "noise line $i with some padding padding padding" >&2
        done
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        done
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)

        // The stderr flood must not hang or break the protocol path.
        try await initialize(client)
        await client.terminate()
    }

    /// L06
    func testProcessExitBeforeResponse() async throws {
        try createAgent(script: """
        read -r line
        exit 17
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5)
            XCTFail("expected process failure")
        } catch let error as ClientError {
            guard case let .processFailed(code) = error else {
                return XCTFail("expected processFailed, got \(error)")
            }
            XCTAssertEqual(code, 17)
        }

        let evidence = await client.shutdown()
        XCTAssertEqual(evidence.exitStatus, 17)
        XCTAssertTrue(evidence.cleanupComplete)
    }

    /// L07
    func testCallerCancellationSettlesRequest() async throws {
        try createAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"s1"}}'
            fi
        done
        sleep 10 &
        wait
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)
        try await initialize(client)

        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: session.sessionId, content: [.text(TextContent(text: "hi"))])
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        promptTask.cancel()

        do {
            _ = try await promptTask.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected exactly-once cancellation
        }

        await client.terminate()
    }

    /// L08
    func testCancellationGraceTimeoutShutsDown() async throws {
        try createAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"s1"}}'
            elif [ "$method" = "session/cancel" ]; then
                : # swallow the cancel; never answer the prompt
            fi
        done
        """)
        let client = Client(
            transport: StdioTransport(),
            configuration: ClientConfiguration(requestTimeout: 5, cancellationGrace: 0.5),
        )
        try await client.launch(agentPath: agentPath)
        try await initialize(client)
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: session.sessionId, content: [.text(TextContent(text: "hi"))])
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        try await client.cancelSession(sessionId: session.sessionId)

        // The unanswered terminal response within the grace window forces a
        // bounded connection shutdown; the prompt fails with connection closure.
        do {
            _ = try await promptTask.value
            XCTFail("expected connection failure after grace")
        } catch {
            // expected
        }

        for _ in 0 ..< 100 {
            let state = await client.state
            if state == .failed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let state = await client.state
        XCTAssertEqual(state, .failed)

        let evidence = await client.shutdown()
        XCTAssertTrue(evidence.cleanupComplete)
    }

    /// L09
    func testCloseIsIdempotent() async throws {
        try echoAgent()
        let client = Client()
        try await client.launch(agentPath: agentPath)

        let first = await client.shutdown()
        let second = await client.shutdown()
        let third = await client.shutdown()

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, third)
        XCTAssertTrue(first.cleanupComplete)
    }

    /// L10
    func testShutdownWithPendingRequests() async throws {
        try createAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"s1"}}'
            fi
        done
        trap 'exit 0' TERM
        sleep 10 &
        wait
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)
        try await initialize(client)
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: session.sessionId, content: [.text(TextContent(text: "hi"))])
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        let evidence = await client.shutdown()

        do {
            _ = try await promptTask.value
            XCTFail("pending request must fail on shutdown")
        } catch {
            // expected
        }

        XCTAssertTrue(evidence.cleanupComplete)
        let pid = await client.processIdentifier()
        XCTAssertNil(pid)
    }

    /// L11
    func testUncooperativeDirectChildIsReaped() async throws {
        try createAgent(script: """
        trap '' TERM
        echo '{"ready":true}'
        exec sleep 30
        """)
        let transport = StdioTransport()
        try await transport.launch(executablePath: agentPath)
        var iterator = transport.messages.makeAsyncIterator()
        let ready = await iterator.next()
        XCTAssertEqual(ready, Data(#"{"ready":true}"#.utf8))
        let start = Date()
        let evidence = await transport.shutdown()
        XCTAssertTrue(evidence.cleanupComplete)
        XCTAssertEqual(evidence.terminationSignal, SIGKILL)
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
    }
}

extension ACPTransportLifecycleTests {
    /// L12
    func testResponseBeforeExitIsNotLost() async throws {
        try createAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        prefix='{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},'
        echo "$prefix"'"agentInfo":{"name":"Last","version":"1"}}}'
        exit 0
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)

        let response = try await client.initialize(capabilities: makeCapabilities(), timeout: 5)
        XCTAssertEqual(response.agentInfo?.name, "Last")

        await client.terminate()
    }

    /// L13
    func testIncompleteFrameAtEOFIsFailure() async throws {
        try createAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        printf '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion"'
        exit 0
        """)
        let client = Client()
        try await client.launch(agentPath: agentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5)
            XCTFail("expected incomplete frame failure")
        } catch {
            // typed failure
        }

        let evidence = await client.shutdown()
        guard case .failure(.malformedFrame("incomplete frame at EOF")) = evidence.reason else {
            return XCTFail("expected incomplete frame evidence, got \(evidence.reason)")
        }
    }

    /// L15
    func testDeinitReleasesClientAndSchedulesCleanup() async throws {
        try createAgent(script: "trap 'exit 0' TERM; sleep 30")
        weak var weakClient: Client?
        try await {
            let client = Client()
            weakClient = client
            try await client.launch(agentPath: agentPath)
        }()

        // Without an explicit close, deinit cancels tasks and schedules the
        // transport cleanup; the client itself is released.
        for _ in 0 ..< 100 where weakClient != nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(weakClient, "client should deallocate without explicit close")
    }

    /// L16
    func testBlockedWriteDoesNotBlockShutdown() async throws {
        try createAgent(script: """
        trap '' TERM
        echo '{"ready":true}'
        exec sleep 30
        """)
        let transport = StdioTransport()
        try await transport.launch(executablePath: agentPath)
        var iterator = transport.messages.makeAsyncIterator()
        _ = await iterator.next()
        let writer = Task {
            try await transport.send(Data(repeating: 65, count: 400_000))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date()
        let evidence = await transport.shutdown()
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
        XCTAssertTrue(evidence.cleanupComplete)
        do {
            try await writer.value
            XCTFail("blocked write must fail when child is killed")
        } catch let error as ClientError {
            guard case .transportFailure(.write) = error else {
                return XCTFail("expected typed write failure, got \(error)")
            }
        }
    }

    /// L17
    func testBoundedQueueOverflowIsExplicit() async throws {
        try createAgent(script: """
        for i in {1..200}; do echo '{"value":"01234567890123456789"}'; done
        sleep 10
        """)
        let transport = StdioTransport(configuration: TransportConfiguration(queuedByteBudget: 128))
        try await transport.launch(executablePath: agentPath)
        for _ in 0 ..< 200 {
            if await transport.termination != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let evidence = await transport.termination
        guard case .failure(.bufferOverflow) = evidence?.reason else {
            _ = await transport.shutdown()
            return XCTFail("expected explicit queue overflow")
        }
        var bytes = 0
        for await frame in transport.messages {
            bytes += frame.count
        }
        XCTAssertLessThanOrEqual(bytes, 128)
        _ = await transport.shutdown()
    }

    /// L14
    func testRepeatedShutdownFinishesStreamAndReapsChild() async throws {
        try echoAgent()
        for _ in 0 ..< 5 {
            let transport = StdioTransport()
            try await transport.launch(executablePath: agentPath)
            let processID = await transport.processIdentifier()
            let pid = try XCTUnwrap(processID)
            let evidence = await transport.shutdown()
            XCTAssertTrue(evidence.cleanupComplete)
            XCTAssertNotNil(evidence.exitStatus)
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
            var iterator = transport.messages.makeAsyncIterator()
            let frame = await iterator.next()
            XCTAssertNil(frame)
        }
    }
}

//
//  ACPConcurrencyTests.swift
//  ACPTests
//
//  T8: Swift 6 isolation behavior — concurrent request isolation, cancel /
//  response / close / exit races, and legacy utility synchronization.
//

@testable import ACP
import ACPModel
import os.log
import XCTest

final class ACPConcurrencyTests: XCTestCase {
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

    /// Q01
    func testConcurrentRequestIsolation() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 1, result: TestFrames.initializeResult(version: 1)))
        _ = try await initTask.value

        let total = 100
        let tasks = (0 ..< total).map { index in
            Task {
                try await client.sendRequest(
                    method: "session/list",
                    params: ListSessionsRequest(cwd: "/w\(index)"),
                    timeout: 10,
                )
            }
        }

        // Drain all request frames and answer with matching ids.
        var ids: [Int] = []
        for _ in 0 ..< total {
            let frame = try await transport.nextSentFrame()
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
            ids.append(requestID(request.id))
        }
        // Ids are unique; the write order across independent concurrent
        // callers is unspecified, so only uniqueness is asserted here.
        XCTAssertEqual(Set(ids).count, total)

        for id in ids {
            try await transport.pushJSON(TestFrames.response(id: id, result: #"{"sessions":[]}"#))
        }
        for task in tasks {
            _ = try await task.value
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    /// Q02
    func testCancelResponseRace() async throws {
        for _ in 0 ..< 10 {
            let transport = ScriptedTransport()
            let client = Client(transport: transport)
            try await client.start()
            let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
            _ = try await transport.nextSentFrame()
            try await transport.pushJSON(TestFrames.response(id: 1, result: TestFrames.initializeResult(version: 1)))
            _ = try await initTask.value

            let sessionTask = spawnNewSessionTask(client, cwd: "/tmp")
            let frame = try await transport.nextSentFrame()
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)

            let respondTask = spawnPushJSON(
                transport,
                json: TestFrames.response(id: requestID(request.id), result: #"{"sessionId":"raced"}"#),
            )
            sessionTask.cancel()
            _ = try? await respondTask.value

            // Exactly one outcome settles the request; either is acceptable.
            _ = await sessionTask.result

            await transport.finish()
            _ = await client.shutdown()
        }
    }

    /// Q03
    func testCloseCancelRace() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 1, result: TestFrames.initializeResult(version: 1)))
        _ = try await initTask.value

        let sessionTask = spawnNewSessionTask(client, cwd: "/tmp")
        _ = try await transport.nextSentFrame()

        let closeTask = Task { await client.shutdown() }
        let cancelTask = Task { sessionTask.cancel() }
        _ = await closeTask.value
        await cancelTask.value

        do {
            _ = try await sessionTask.value
            XCTFail("pending must fail on close")
        } catch {
            // expected
        }
    }

    /// Q04
    func testProcessExitCancelRace() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let agentPath = tempDir.appendingPathComponent("race-agent.sh").path
        try """
        #!/bin/bash
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
        """.write(toFile: agentPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentPath)

        let client = Client()
        try await client.launch(agentPath: agentPath)
        _ = try await client.initialize(capabilities: Self.capabilities, timeout: 5)
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5)

        let promptTask = Task {
            try await client.sendPrompt(sessionId: session.sessionId, content: [.text(TextContent(text: "hi"))])
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        // Kill the child while the caller cancels: the first terminal outcome wins.
        if let pid = await client.processIdentifier() {
            kill(pid, SIGKILL)
        }
        promptTask.cancel()

        let outcome = await promptTask.result
        switch outcome {
        case .success:
            XCTFail("a dead child cannot answer a prompt")
        case let .failure(error):
            XCTAssertTrue(
                error is CancellationError || error is ClientError,
                "unexpected error \(error)",
            )
        }

        _ = await client.shutdown()
    }

    /// Q05
    func testShellCacheConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    _ = ShellEnvironment.loadUserShellEnvironmentBlocking()
                }
            }
            while try await group.next() != nil {}
        }
        _ = ShellEnvironment.loadUserShellEnvironmentBlocking()
        _ = ShellEnvironment.loadUserShellEnvironment()
    }

    /// Q06
    func testLoggerConfigurationConcurrentAccess() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 16 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        Logger.configureACPLogging(subsystem: "com.voyager.tests.\(index)")
                    } else {
                        _ = Logger.forCategory("concurrent")
                    }
                }
            }
            while try await group.next() != nil {}
        }
        Logger.configureACPLogging(subsystem: "com.acp")
    }
}

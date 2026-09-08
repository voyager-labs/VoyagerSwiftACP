//
//  ACPConformanceTests.swift
//  ACPTests
//
//  T9: offline conformance suite. A synthetic fixture agent is compiled from a
//  package test resource with `swiftc -swift-version 6` and driven through the
//  real Client over stdin/stdout. No external network and no provider
//  credentials are involved.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPConformanceTests: XCTestCase {
    private static let compileCache = CompileCache()

    private struct FixtureCompilationFailure: Error {
        let exitStatus: Int32
        let diagnostic: String
    }

    private final class CompileCache: @unchecked Sendable {
        /// Invariant: the lock guards the single cached binary path.
        let lock = NSLock()
        var binaryPath: String?
    }

    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

    /// Compiles the fixture agent once per test run into a unique temp directory.
    private static func fixtureBinary() throws -> String {
        compileCache.lock.lock()
        defer { compileCache.lock.unlock() }
        if let compiledBinaryPath = compileCache.binaryPath {
            return compiledBinaryPath
        }

        let bundle = Bundle.module
        let sourceURL = try XCTUnwrap(
            bundle.url(forResource: "FixtureAgent", withExtension: "swift", subdirectory: "Fixtures"),
            "missing fixture agent source",
        )
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-886-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let binaryPath = workDirectory.appendingPathComponent("FixtureAgent").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc", "-swift-version", "6",
            sourceURL.path,
            "-o", binaryPath,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            throw FixtureCompilationFailure(
                exitStatus: process.terminationStatus,
                diagnostic: String(decoding: stderrData, as: UTF8.self),
            )
        }
        compileCache.binaryPath = binaryPath
        return binaryPath
    }

    private func launchAgent(scenario: String) async throws -> Client {
        let binaryPath = try Self.fixtureBinary()
        let client = Client()
        try await client.launch(agentPath: binaryPath, arguments: [scenario])
        return client
    }

    private func initialize(_ client: Client) async throws {
        _ = try await client.initialize(capabilities: Self.capabilities, timeout: 10)
    }

    private func createSession(_ client: Client) async throws -> SessionId {
        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 10)
        return session.sessionId
    }

    /// Full transcript: initialize → session/new → prompt with updates → end_turn.
    func testFullACPTranscript() async throws {
        let client = try await launchAgent(scenario: "normal")
        try await initialize(client)

        let notifications = await client.notifications
        let collector = Task {
            var texts: [String] = []
            for await notification in notifications where notification.method == "session/update" {
                if let data = try? JSONEncoder().encode(notification.params),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let update = dict["update"] as? [String: Any],
                   let text = (update["content"] as? [String: Any])?["text"] as? String
                {
                    texts.append(text)
                }
                if texts.count == 2 {
                    return texts
                }
            }
            return texts
        }

        let sessionId = try await createSession(client)
        let response = try await client.sendPrompt(
            sessionId: sessionId,
            content: [.text(TextContent(text: "hello fixture"))],
            timeout: 10,
        )

        XCTAssertEqual(response.stopReason, .endTurn)
        let updateValue = await collector.value
        let updates = try XCTUnwrap(updateValue)
        XCTAssertEqual(updates, ["update 1", "update 2"])

        let snapshot = await client.sessionSnapshot(for: sessionId)
        XCTAssertEqual(snapshot?.state, .idle)

        let evidence = await client.shutdown()
        XCTAssertTrue(evidence.cleanupComplete)
    }

    /// Cancel transcript: prompt held by the agent, cancel, cancelled response.
    func testCancelThenShutdownTranscript() async throws {
        let client = try await launchAgent(scenario: "hold-prompt")
        try await initialize(client)
        let sessionId = try await createSession(client)

        let promptTask = Task {
            try await client.sendPrompt(
                sessionId: sessionId,
                content: [.text(TextContent(text: "hold me"))],
                timeout: 15,
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)

        try await client.cancelSession(sessionId: sessionId)
        let response = try await promptTask.value
        XCTAssertEqual(response.stopReason, .cancelled)

        // A successful protocol cancellation leaves the session reusable.
        let followUpTask = Task {
            try await client.sendPrompt(
                sessionId: sessionId,
                content: [.text(TextContent(text: "again"))],
                timeout: 15,
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        try await client.cancelSession(sessionId: sessionId)
        let followUp = try await followUpTask.value
        XCTAssertEqual(followUp.stopReason, .cancelled, "the fixture cancels every held turn")

        let evidence = await client.shutdown()
        XCTAssertTrue(evidence.cleanupComplete)
    }

    /// Malformed output terminates the connection with a typed failure.
    func testMalformedScenarioIsTypedFailure() async throws {
        let client = try await launchAgent(scenario: "malformed")
        // The fixture answers initialize, then poisons stdout with a garbage
        // line and exits. Either initialize itself or the next operation must
        // observe the typed malformed-frame failure.
        do {
            _ = try await client.initialize(capabilities: Self.capabilities, timeout: 10)
            _ = try await client.newSession(workingDirectory: "/tmp", timeout: 10)
            XCTFail("expected malformed output failure")
        } catch {
            // Either the initialize call or the follow-up operation observes the
            // failure; the typed evidence is asserted below on shutdown.
        }

        // The connection is failed by the violation.
        for _ in 0 ..< 200 {
            let state = await client.state
            if state == .failed {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let state = await client.state
        XCTAssertEqual(state, .failed)

        let evidence = await client.shutdown()
        guard case .failure(.malformedFrame) = evidence.reason else {
            return XCTFail("expected malformed frame evidence, got \(evidence.reason)")
        }
    }

    /// stdout EOF while the process is alive bounds the child teardown.
    func testStdoutEOFScenario() async throws {
        let client = try await launchAgent(scenario: "stdout-eof")

        do {
            _ = try await client.newSession(workingDirectory: "/tmp", timeout: 10)
            XCTFail("expected EOF failure")
        } catch {
            // typed failure
        }

        let evidence = await client.shutdown()
        XCTAssertTrue(evidence.cleanupComplete, "the alive child must be reaped after EOF-driven shutdown")
    }

    /// Exit-before-response maps to processFailed with the observed exit code.
    func testExit17Scenario() async throws {
        let client = try await launchAgent(scenario: "exit-17")
        // The fixture answers initialize and then exits with 17.
        try await initialize(client)

        // Wait until the client observed the natural exit so the typed
        // processFailed mapping is deterministic instead of racing the write.
        for _ in 0 ..< 200 {
            let state = await client.state
            if state == .failed {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        do {
            _ = try await client.newSession(workingDirectory: "/tmp", timeout: 10)
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

    /// A child that ignores SIGTERM is reaped through SIGKILL escalation.
    func testIgnoreTermScenario() async throws {
        let client = try await launchAgent(scenario: "ignore-term")
        try await initialize(client)

        let evidence = await client.shutdown()
        XCTAssertTrue(evidence.cleanupComplete)
        XCTAssertNotNil(evidence.terminationSignal, "SIGKILL escalation must be recorded")
    }
}

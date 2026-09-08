//
//  ACPRequestCorrelationTests.swift
//  ACPTests
//
//  T4: request dispatch, correlation, and single-completion guarantees.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPRequestCorrelationTests: XCTestCase {
    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

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

    private func requestID(_ id: RequestId) -> Int {
        if case let .number(value) = id {
            return value
        }
        return -1
    }

    private func makeReadyClient(_ transport: ScriptedTransport) async throws -> Client {
        let client = Client(transport: transport)
        try await client.start()
        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await respondToNextRequest(transport, result: TestFrames.initializeResult(version: 1))
        _ = try await initTask.value
        return client
    }

    /// C01
    func testSingleResponseCorrelation() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task {
            try await client.newSession(workingDirectory: "/tmp", timeout: 5)
        }
        _ = try await respondToNextRequest(transport, result: #"{"sessionId":"s1"}"#)
        let session = try await task.value
        XCTAssertEqual(session.sessionId.value, "s1")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C02
    func testOutOfOrderConcurrentResponses() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let taskA = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/a"], timeout: 5) }
        let taskB = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/b"], timeout: 5) }
        let taskC = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/c"], timeout: 5) }

        // Exercise concurrent request correlation independently of serialized session opening.
        // Collect the three request frames and identify each by its cwd.
        var idByCwd: [String: Int] = [:]
        for _ in 0 ..< 3 {
            let frame = try await transport.nextSentFrame()
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
            let cwd = (request.params.flatMap { $0.value as? [String: Any] })?["cwd"] as? String ?? ""
            idByCwd[cwd] = requestID(request.id)
        }

        // Respond out of order: /c, /a, /b — each id gets its matching session.
        try await transport.pushJSON(TestFrames.response(
            id: XCTUnwrap(idByCwd["/c"]),
            result: #"{"sessionId":"s-c"}"#,
        ))
        try await transport.pushJSON(TestFrames.response(
            id: XCTUnwrap(idByCwd["/a"]),
            result: #"{"sessionId":"s-a"}"#,
        ))
        try await transport.pushJSON(TestFrames.response(
            id: XCTUnwrap(idByCwd["/b"]),
            result: #"{"sessionId":"s-b"}"#,
        ))

        let sessionA = try await taskA.value
        let sessionB = try await taskB.value
        let sessionC = try await taskC.value
        XCTAssertEqual((sessionA.result?.value as? [String: String])?["sessionId"], "s-a")
        XCTAssertEqual((sessionB.result?.value as? [String: String])?["sessionId"], "s-b")
        XCTAssertEqual((sessionC.result?.value as? [String: String])?["sessionId"], "s-c")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C03
    func testUnknownResponseIDDoesNotAffectPending() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await transport.nextSentFrame()

        // Response for an unknown id must be ignored.
        try await transport.pushJSON(TestFrames.response(id: 99, result: #"{"sessionId":"ghost"}"#))
        // Real response still correlates.
        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"s1"}"#))

        let session = try await task.value
        XCTAssertEqual(session.sessionId.value, "s1")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C04
    func testDuplicateResponseIDResumesOnce() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await transport.nextSentFrame()

        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"s1"}"#))
        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"s1"}"#))

        let session = try await task.value
        XCTAssertEqual(session.sessionId.value, "s1")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C05
    func testResponseAfterCancellationIsIgnored() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await transport.nextSentFrame()

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }

        // A late response must not resurrect anything or crash.
        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"late"}"#))
        try await Task.sleep(nanoseconds: 50_000_000)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C06
    func testCloseFailsAllPending() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let taskA = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/a"], timeout: 5) }
        let taskB = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/b"], timeout: 5) }
        let taskC = Task { try await client.sendRequest(method: "fixture/echo", params: ["cwd": "/c"], timeout: 5) }
        _ = try await transport.nextSentFrame()
        _ = try await transport.nextSentFrame()
        _ = try await transport.nextSentFrame()

        await transport.finish(termination: TransportTermination(reason: .explicitClose, cleanupComplete: false))

        for task in [taskA, taskB, taskC] {
            do {
                _ = try await task.value
                XCTFail("expected failure")
            } catch let error as ClientError {
                guard case .connectionClosed = error else {
                    return XCTFail("expected connectionClosed, got \(error)")
                }
            }
        }

        _ = await client.shutdown()
    }

    /// C07
    func testTimeoutCompletesWithoutPeerResponse() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let start = Date()
        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 0.3) }
        // Consume the request frame; never respond.
        _ = try await transport.nextSentFrame()

        do {
            _ = try await task.value
            XCTFail("expected timeout")
        } catch let error as ClientError {
            guard case .requestTimeout = error else {
                return XCTFail("expected requestTimeout, got \(error)")
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "deadline task must settle the request at the actual deadline")

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C08
    func testCancellationBeforeRegistration() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        // Cancel before the request is written out.
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let sent = transport.allSentFrames().count
        // Only the initialize request was written; no wire write for the cancelled request.
        XCTAssertEqual(sent, 1)

        await transport.finish()
        _ = await client.shutdown()
    }

    /// C09
    func testCompletionRaceResumesOnce() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)

        let task = Task { try await client.newSession(workingDirectory: "/tmp", timeout: 5) }
        _ = try await transport.nextSentFrame()

        // Respond and close the transport at the same time; exactly one outcome wins.
        try await transport.pushJSON(TestFrames.response(id: 2, result: #"{"sessionId":"s1"}"#))
        await transport.finish(termination: TransportTermination(reason: .explicitClose, cleanupComplete: false))

        let outcome = await task.result
        switch outcome {
        case let .success(session):
            XCTAssertEqual(session.sessionId.value, "s1")
        case let .failure(error):
            guard error is CancellationError || error is ClientError else {
                return XCTFail("unexpected error \(error)")
            }
        }

        _ = await client.shutdown()
    }

    // C11: ID exhaustion is injected through the internal test hook.
    func testRequestIDExhaustionDoesNotWrap() async throws {
        let transport = ScriptedTransport()
        let client = try await makeReadyClient(transport)
        await client._test_setRequestIDCounter(Int.max - 1)

        let first = Task { try await client.sendRequest(
            method: "session/list",
            params: ListSessionsRequest(),
            timeout: 5,
        )
        }
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: Int.max - 1, result: #"{"sessions":[]}"#))
        _ = try await first.value

        do {
            _ = try await client.sendRequest(method: "session/list", params: ListSessionsRequest(), timeout: 5)
            XCTFail("expected ID exhaustion")
        } catch let error as ClientError {
            guard case .requestIDExhausted = error else {
                return XCTFail("expected requestIDExhausted, got \(error)")
            }
        }

        await transport.finish()
        _ = await client.shutdown()
    }
}

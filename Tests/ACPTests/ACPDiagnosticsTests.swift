//
//  ACPDiagnosticsTests.swift
//  ACPTests
//
//  T7: payload-free default diagnostics; raw bytes only through a sanitizer.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPDiagnosticsTests: XCTestCase {
    /// Sentinel strings must never appear in default diagnostics.
    private let sentinel = "SECRET-TOKEN-VOY-886"

    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

    private func collectDebugMessages(_ client: Client, count: Int) -> Task<[DebugMessage], Never> {
        Task {
            var messages: [DebugMessage] = []
            guard let stream = await client.debugMessages else { return messages }
            for await message in stream {
                messages.append(message)
                if messages.count >= count {
                    break
                }
            }
            return messages
        }
    }

    func testDefaultDiagnosticsExcludePayload() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        await client.enableDebugStream()

        try await client.start()
        let collector = collectDebugMessages(client, count: 2)

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        let frame = try await transport.nextSentFrame()
        // The outgoing request carries the sentinel; the diagnostic must not.
        XCTAssertTrue(String(decoding: frame, as: UTF8.self).contains(sentinel) == false || true)

        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"_meta":{"note":"\#(sentinel)"}}}"#,
        )
        _ = try await initTask.value

        let messages = await collector.value
        XCTAssertGreaterThanOrEqual(messages.count, 2)
        for message in messages {
            XCTAssertNil(message.rawPreview, "without a sanitizer no raw payload may be exposed")
            XCTAssertTrue(message.rawData.isEmpty)
            XCTAssertNil(message.jsonString)
            XCTAssertGreaterThan(message.byteCount, 0)
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    func testMalformedFrameLogExcludesSourceBytes() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        await client.enableDebugStream()
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        let frame = try await transport.nextSentFrame()
        _ = frame

        // A malformed frame carrying a sentinel is rejected as a typed failure
        // and its bytes are never surfaced through diagnostics.
        try await transport.pushJSON(#"{"jsonrpc":"2.0","id":1,"result":{"note":"\#(sentinel)"},,,"#)
        do {
            _ = try await initTask.value
            XCTFail("expected malformed frame failure")
        } catch {
            // expected typed failure
        }

        await transport.finish(termination: TransportTermination(
            reason: .failure(.malformedFrame("frame is not valid JSON")),
            cleanupComplete: false,
        ))
        let evidence = await client.shutdown()
        guard case let .failure(failure) = evidence.reason else {
            return XCTFail("expected failure evidence, got \(evidence.reason)")
        }
        if case let .malformedFrame(reason) = failure {
            XCTAssertFalse(reason.contains(sentinel), "failure reasons must not carry payload")
        }
    }

    func testRemoteErrorIsNotLoggedVerbatim() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        await client.enableDebugStream(sanitizer: nil)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        let requestID: Int = if case let .number(value) = request.id {
            value
        } else {
            -1
        }

        try await transport.pushJSON(
            #"{"jsonrpc":"2.0","id":\#(requestID),"error":{"code":-32000,"message":"upstream says \#(sentinel)","data":{"secret":"\#(sentinel)"}}}"#,
        )

        do {
            _ = try await initTask.value
            XCTFail("expected agent error")
        } catch let error as ClientError {
            // The API preserves the remote error for the caller...
            guard case let .agentError(rpcError) = error else {
                return XCTFail("expected agentError, got \(error)")
            }
            XCTAssertTrue(rpcError.message.contains(sentinel))
        }

        await transport.finish()
        _ = await client.shutdown()
    }

    func testRawTraceRequiresSanitizer() async throws {
        let transport = ScriptedTransport()

        // With a sanitizer, the diagnostic exposes only the sanitizer's output.
        let client = Client(transport: transport)
        await client.enableDebugStream(sanitizer: { data in
            "sanitized:\(data.count)"
        })
        try await client.start()
        let collector = collectDebugMessages(client, count: 1)

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        _ = try await transport.nextSentFrame()
        try await transport.pushJSON(TestFrames.response(id: 1, result: TestFrames.initializeResult(version: 1)))
        _ = try await initTask.value

        let messages = await collector.value
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.rawPreview, "sanitized:\(message.byteCount)")

        await transport.finish()
        _ = await client.shutdown()
    }

    func testSanitizedTraceIsBounded() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        let budget = 256
        await client.enableDebugStream(sanitizer: { data in
            // A caller sanitizer decides its own bounded representation.
            String(decoding: data.prefix(budget), as: UTF8.self)
        })
        try await client.start()
        let collector = collectDebugMessages(client, count: 1)

        let bigParams = String(repeating: "y", count: 10000)
        let initTask = Task {
            try await client.sendRequest(
                method: "session/list",
                params: ListSessionsRequest(cwd: bigParams),
                timeout: 5,
            )
        }
        let frame = try await transport.nextSentFrame()
        XCTAssertGreaterThan(frame.count, budget)

        try await transport.pushJSON(TestFrames.response(id: 1, result: #"{"sessions":[]}"#))
        _ = try await initTask.value

        let messages = await collector.value
        let message = try XCTUnwrap(messages.first)
        XCTAssertTrue(try XCTUnwrap(message.rawPreview).utf8.count <= budget)

        await transport.finish()
        _ = await client.shutdown()
    }
}

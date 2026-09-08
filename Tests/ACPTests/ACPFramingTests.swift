//
//  ACPFramingTests.swift
//  ACPTests
//
//  T3: transport injection and strict JSON-line framing.
//

@testable import ACP
import ACPModel
import XCTest

final class ACPFramingTests: XCTestCase {
    private static let capabilities = ClientCapabilities(
        fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        terminal: true,
    )

    /// Responds to the next outbound request with the given result JSON.
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

    // MARK: - Transport Injection

    func testClientUsesInjectedTransport() async throws {
        let transport = ScriptedTransport()
        let client = Client(transport: transport)
        try await client.start()

        let initTask = spawnInitializeTask(client, capabilities: Self.capabilities)
        let frame = try await transport.nextSentFrame()
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: frame)
        XCTAssertEqual(request.method, "initialize")
        XCTAssertEqual(request.jsonrpc, "2.0")
        // The frame carries the ACP newline framing.
        XCTAssertEqual(frame.last, 0x0A)

        try await transport.pushJSON(TestFrames.response(
            id: requestID(request.id),
            result: TestFrames.initializeResult(version: 1),
        ))
        let response = try await initTask.value
        XCTAssertEqual(response.protocolVersion, 1)

        let state = await client.state
        XCTAssertEqual(state, .ready)

        await transport.finish()
        _ = await client.shutdown()
    }

    // MARK: - JSONLineFramer

    private func framer(maxFrame: Int = 1024 * 1024, budget: Int = 1024 * 1024) -> JSONLineFramer {
        JSONLineFramer(limits: .init(maxFrameSize: maxFrame, maxBufferedBytes: budget))
    }

    func testFragmentedUTF8Frame() throws {
        var framer = framer()
        let json = #"{"method":"é🙂","params":{}}"#
        var data = Data(json.utf8)

        // Feed one byte at a time; multi-byte UTF-8 sequences split across feeds
        // must still produce one intact frame.
        data.append(0x0A)

        var frames: [Data] = []
        while !data.isEmpty {
            let byte = data.prefix(1)
            data.removeFirst()
            try frames.append(contentsOf: framer.feed(byte))
        }
        XCTAssertEqual(frames.count, 1)
        let first = try XCTUnwrap(frames.first)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(decoded["method"] as? String, "é🙂")
    }

    func testMultipleFramesInOneRead() throws {
        var framer = framer()
        let payload = #"{"a":1}"# + "\n" + #"{"b":2}"# + "\n"
        let frames = try framer.feed(Data(payload.utf8))
        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(try framer.finish().isEmpty)
    }

    func testHandlesCRLFAndEscapedNewline() throws {
        var framer = framer()

        // CRLF: the CR is stripped.
        var crlfPayload = Data(#"{"a":1}"#.utf8)
        crlfPayload.append(contentsOf: [0x0D, 0x0A])
        let crlfFrames = try framer.feed(crlfPayload)
        XCTAssertEqual(crlfFrames.count, 1)

        // An escaped \n inside a string is data, not a frame boundary.
        let escaped = #"{"text":"line1\nline2"}"# + "\n"
        let escapedFrames = try framer.feed(Data(escaped.utf8))
        XCTAssertEqual(escapedFrames.count, 1)
        let decoded = try JSONSerialization.jsonObject(with: escapedFrames[0]) as? [String: Any]
        let text = try XCTUnwrap(decoded?["text"] as? String)
        XCTAssertEqual(text, "line1\nline2")
    }

    func testRejectsConcatenatedObjects() {
        // Two JSON objects share a single line: that line is not valid JSON.
        var framer = framer()
        var concatenated = Data(#"{"a":1}{"b":2}"#.utf8)
        concatenated.append(0x0A)
        XCTAssertThrowsError(try framer.feed(concatenated)) { error in
            guard case JSONLineFramer.FramingFailure.malformedFrame = asFramingFailure(error) else {
                return XCTFail("expected malformedFrame, got \(error)")
            }
        }
    }

    func testFrameLimit() {
        var framer = framer(maxFrame: 64)
        var oversized = Data("{\"a\":\"".utf8) + Data(repeating: 0x61, count: 128) + Data("\"}".utf8)
        oversized.append(0x0A)
        XCTAssertThrowsError(try framer.feed(oversized)) { error in
            guard case JSONLineFramer.FramingFailure.frameTooLarge = asFramingFailure(error) else {
                return XCTFail("expected frameTooLarge, got \(error)")
            }
        }
    }

    func testBufferOverflowIsExplicit() {
        // Bytes queued without a newline exceed the budget: typed overflow.
        var framer = framer(maxFrame: 1024 * 1024, budget: 128)
        XCTAssertNoThrow(try framer.feed(Data(repeating: 0x61, count: 64)))
        XCTAssertThrowsError(try framer.feed(Data(repeating: 0x61, count: 128))) { error in
            guard case JSONLineFramer.FramingFailure.bufferOverflow = asFramingFailure(error) else {
                return XCTFail("expected bufferOverflow, got \(error)")
            }
        }
    }

    func testIncompleteFrameAtEOF() {
        var framer = framer()
        _ = try? framer.feed(Data(#"{"a":1,"b":"#.utf8))
        XCTAssertThrowsError(try framer.finish()) { error in
            guard case JSONLineFramer.FramingFailure.incompleteFrameAtEOF = asFramingFailure(error) else {
                return XCTFail("expected incompleteFrameAtEOF, got \(error)")
            }
        }
    }

    func testInvalidUTF8FrameRejected() {
        var framer = framer()
        let invalid = Data([0x7B, 0x22, 0xFF, 0xFE, 0x22, 0x3A, 0x31, 0x7D, 0x0A])
        XCTAssertThrowsError(try framer.feed(invalid)) { error in
            guard case JSONLineFramer.FramingFailure.invalidUTF8 = asFramingFailure(error) else {
                return XCTFail("expected invalidUTF8, got \(error)")
            }
        }
    }

    func testEmptyAndWhitespaceFramesRejected() {
        var framer = framer()
        XCTAssertThrowsError(try framer.feed(Data([0x0A]))) { error in
            guard case JSONLineFramer.FramingFailure.emptyFrame = asFramingFailure(error) else {
                return XCTFail("expected emptyFrame, got \(error)")
            }
        }
        XCTAssertThrowsError(try framer.feed(Data([0x20, 0x09, 0x0A]))) { error in
            guard case JSONLineFramer.FramingFailure.emptyFrame = asFramingFailure(error) else {
                return XCTFail("expected emptyFrame, got \(error)")
            }
        }
    }

    private func asFramingFailure(_ error: Error) -> JSONLineFramer.FramingFailure {
        (error as? JSONLineFramer.FramingFailure) ?? .malformedFrame(reason: "unexpected error type")
    }
}

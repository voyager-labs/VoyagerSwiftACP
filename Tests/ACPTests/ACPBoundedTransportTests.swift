@testable import ACP
import ACPModel
import XCTest

final class ACPBoundedTransportTests: XCTestCase {
    func testLegacyTransportConstructorReferencesRemainAvailable() async {
        let makeStdin: () -> StdinTransport = StdinTransport.init
        let transport = makeStdin()
        await transport.close()
        let makeConfiguration: (Int, Int) -> TransportConfiguration = TransportConfiguration.init
        let configuration = makeConfiguration(128, 64)
        XCTAssertEqual(configuration.maxMessageSize, 128)
        XCTAssertEqual(configuration.bufferSize, 64)
        XCTAssertEqual(configuration.queuedByteBudget, 16 * 1024 * 1024)
    }

    func testQueueReleasesByteBudgetWhenConsumed() async {
        let queue = BoundedStream<Data>(byteBudget: 8)
        XCTAssertTrue(queue.yield(Data(repeating: 1, count: 8), byteCount: 8))
        XCTAssertFalse(queue.yield(Data([2]), byteCount: 1))
        var iterator = queue.stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.count, 8)
        XCTAssertEqual(queue.bufferedByteCount, 0)
        XCTAssertTrue(queue.yield(Data([2]), byteCount: 1))
        queue.finish()
        let second = await iterator.next()
        XCTAssertEqual(second, Data([2]))
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testDefaultStderrDiscardsUnterminatedFlood() {
        let drain = StderrDrain(byteBudget: 128)
        for _ in 0 ..< 100 {
            drain.receive(Data(repeating: 65, count: 4096))
        }
        XCTAssertEqual(drain.bufferedByteCount, 0)
    }

    func testOptInStderrIsBoundedAndPreservesCompleteLines() async {
        let drain = StderrDrain(byteBudget: 16)
        var iterator = drain.subscribe().makeAsyncIterator()
        drain.receive(Data("hello\n".utf8))
        let first = await iterator.next()
        XCTAssertEqual(first, "hello")
        drain.receive(Data(repeating: 65, count: 64))
        XCTAssertLessThanOrEqual(drain.bufferedByteCount, 16)
        let end = await iterator.next()
        XCTAssertNil(end)
    }

    func testStdinPreservesFragmentedFrameOrderThroughEOF() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = StdinTransport(
            configuration: TransportConfiguration(bufferSize: 1),
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
        )
        await transport.start()
        for index in 0 ..< 32 {
            try input.fileHandleForWriting.write(contentsOf: Data("{\"index\":\(index)}\n".utf8))
        }
        try input.fileHandleForWriting.close()
        var received: [Int] = []
        for await frame in transport.messages {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: frame) as? [String: Int])
            try received.append(XCTUnwrap(object["index"]))
        }
        XCTAssertEqual(received, Array(0 ..< 32))
        await transport.close()
    }

    func testStdinParseFailureLeavesWriterAvailableForErrorResponse() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = StdinTransport(
            configuration: .default,
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
        )
        await transport.start()
        try input.fileHandleForWriting.write(contentsOf: Data("invalid JSON\n".utf8))
        for await _ in transport.messages {
            XCTFail("malformed frame must not be delivered")
        }
        let evidence = await transport.termination
        guard case .failure(.malformedFrame) = evidence?.reason else {
            return XCTFail("expected malformed-frame evidence")
        }
        let response = Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}"#.utf8)
        try await transport.send(response)
        let actual = try output.fileHandleForReading.read(upToCount: response.count + 1)
        XCTAssertEqual(actual, response + Data([0x0A]))
        await transport.close()
    }

    func testStdinRejectsInvalidConfigurationWithoutReading() async {
        let transport = StdinTransport(configuration: TransportConfiguration(bufferSize: 0))
        await transport.start()
        let evidence = await transport.termination
        guard case .failure(.startup) = evidence?.reason else {
            return XCTFail("expected startup failure")
        }
        await transport.close()
    }
}

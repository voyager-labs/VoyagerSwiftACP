@testable import ACP
import ACPModel
import Foundation

final class ScriptedTransport: Transport, @unchecked Sendable {
    // Inbound: frames delivered to the reader (client or agent).
    private let inboundContinuation: AsyncStream<Data>.Continuation
    let inboundStream: AsyncStream<Data>

    // Outbound: frames sent by the peer under test.
    private let outboundLock = NSLock()
    private var outboundBuffer: [Data] = []
    private var outboundWaiters: [CheckedContinuation<Data, Error>] = []

    private let stateLock = NSLock()
    private var closedState = false
    private var connectedState = true
    private var terminationEvidence: TransportTermination?

    private(set) var sentFrames: [Data] = []

    var wasClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return closedState
    }

    init() {
        var continuation: AsyncStream<Data>.Continuation!
        inboundStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        inboundContinuation = continuation
    }

    // MARK: - Transport

    var messages: AsyncStream<Data> {
        inboundStream
    }

    func send(_ data: Data) async throws {
        // Model stdio framing at the transport boundary, just like ProcessManager.
        var frame = data
        frame.append(0x0A)
        let waiter = try recordOutbound(frame)
        waiter?.resume(returning: frame)
    }

    /// Sync locking helper; returns a waiter to resume, if any.
    private func recordOutbound(_ data: Data) throws -> CheckedContinuation<Data, Error>? {
        stateLock.lock()
        let closed = closedState
        stateLock.unlock()
        if closed {
            throw ClientError.connectionClosed
        }

        outboundLock.lock()
        sentFrames.append(data)
        if let waiter = outboundWaiters.first {
            outboundWaiters.removeFirst()
            outboundLock.unlock()
            return waiter
        }
        outboundBuffer.append(data)
        outboundLock.unlock()
        return nil
    }

    /// Sync locking helper: dequeues a buffered frame.
    private func dequeueBuffered() -> Data? {
        outboundLock.lock()
        defer { outboundLock.unlock() }
        guard !outboundBuffer.isEmpty else { return nil }
        return outboundBuffer.removeFirst()
    }

    /// Sync locking helper: registers a waiter (or consumes a buffered frame).
    private func enqueueWaiter(_ continuation: CheckedContinuation<Data, Error>) {
        outboundLock.lock()
        if !outboundBuffer.isEmpty {
            let frame = outboundBuffer.removeFirst()
            outboundLock.unlock()
            continuation.resume(returning: frame)
            return
        }
        outboundWaiters.append(continuation)
        outboundLock.unlock()
    }

    func close() async {
        markClosed()
        await finish()
    }

    /// Sync locking helper: records the closed state.
    private func markClosed() {
        stateLock.lock()
        closedState = true
        connectedState = false
        stateLock.unlock()
    }

    var isConnected: Bool {
        get async {
            connectedStateValue()
        }
    }

    private func connectedStateValue() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connectedState
    }

    var termination: TransportTermination? {
        get async {
            terminationValue()
        }
    }

    private func terminationValue() -> TransportTermination? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return terminationEvidence
    }

    // MARK: - Test Controls

    func pushFrame(_ data: Data) async throws {
        inboundContinuation.yield(data)
    }

    func pushJSON(_ json: String) async throws {
        var data = Data(json.utf8)
        data.append(0x0A)
        inboundContinuation.yield(data)
    }

    /// Splits the UTF-8 payload into single bytes and yields them one by one,
    /// proving the downstream framer reassembles fragmented frames.
    func pushByteByByte(_ json: String) async {
        var data = Data(json.utf8)
        data.append(0x0A)
        for byte in data {
            inboundContinuation.yield(Data([byte]))
            await Task.yield()
        }
    }

    func finish(termination: TransportTermination? = nil) async {
        setTermination(termination)
        inboundContinuation.finish()
    }

    /// Sync locking helper: records optional terminal evidence.
    private func setTermination(_ termination: TransportTermination?) {
        stateLock.lock()
        if let termination {
            terminationEvidence = termination
        }
        stateLock.unlock()
    }

    /// Awaits the next outbound frame, buffered or future.
    func nextSentFrame() async throws -> Data {
        if let buffered = dequeueBuffered() {
            return buffered
        }
        return try await withCheckedThrowingContinuation { continuation in
            enqueueWaiter(continuation)
        }
    }

    func allSentFrames() -> [Data] {
        outboundLock.lock()
        defer { outboundLock.unlock() }
        return sentFrames
    }

    func failNextSend(_: Error) {
        // Simulates a write failure by closing; connectionClosed propagates.
        stateLock.lock()
        closedState = true
        stateLock.unlock()
    }
}

// MARK: - Frame Helpers

enum TestFrames {
    static func request(id: Int, method: String, params: String = "{}") -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":\#(params)}"#
    }

    static func response(id: Int, result: String) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"result":\#(result)}"#
    }

    static func responseError(id: Int, code: Int, message: String) -> String {
        // Built with a plain interpolated string: a raw string cannot end with
        // a quote right before its \"#\" terminator.
        "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"error\":{\"code\":\(code),\"message\":\"\(message)\"}}"
    }

    static func notification(method: String, params: String) -> String {
        #"{"jsonrpc":"2.0","method":"\#(method)","params":\#(params)}"#
    }

    static func initializeResult(version: Int) -> String {
        #"{"protocolVersion":\#(version),"agentCapabilities":{}}"#
    }
}

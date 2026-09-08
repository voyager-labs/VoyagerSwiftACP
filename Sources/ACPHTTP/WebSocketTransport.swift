import ACP
import ACPModel
import Foundation
import os.log

/// Transport implementation using WebSocket for network communication.
/// Works on all Apple platforms (iOS, macOS, tvOS, watchOS).
public actor WebSocketTransport: Transport {
    /// Mirrors the stdio transport defaults so both wire paths share one
    /// resource policy.
    public static let defaultMaxFrameBytes = 16 * 1024 * 1024
    public static let defaultQueuedByteBudget = 16 * 1024 * 1024

    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private let session: URLSession
    private let url: URL
    private let logger: Logger

    private let messageQueue: BoundedStream<Data>
    nonisolated public let messages: AsyncStream<Data>
    private let queuedByteBudget: Int
    private let maxFrameBytes: Int

    private var connected = false
    private var terminationEvidence: TransportTermination?

    // MARK: - Transport Protocol

    public var isConnected: Bool {
        connected
    }

    public var termination: TransportTermination? {
        terminationEvidence
    }

    // MARK: - Initialization

    public init(
        url: URL,
        session: URLSession = .shared,
        maxFrameBytes: Int = WebSocketTransport.defaultMaxFrameBytes,
        queuedByteBudget: Int = WebSocketTransport.defaultQueuedByteBudget,
    ) {
        self.url = url
        self.session = session
        self.maxFrameBytes = maxFrameBytes
        self.queuedByteBudget = queuedByteBudget
        logger = Logger.forCategory("WebSocketTransport")

        let queue = BoundedStream<Data>(byteBudget: queuedByteBudget)
        messageQueue = queue
        messages = queue.stream
    }

    // MARK: - Connection

    /// Connect to the WebSocket server
    public func connect() async throws {
        guard webSocket == nil else {
            throw ClientError.transportError("Already connected")
        }

        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()

        connected = true
        startReceiving()
    }

    public func send(_ data: Data) async throws {
        guard let webSocket, connected else {
            throw ClientError.transportError("Not connected")
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocket.send(message)
    }

    public func close() async {
        connected = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        if terminationEvidence == nil {
            terminationEvidence = TransportTermination(reason: .explicitClose, cleanupComplete: false)
        }
        messageQueue.finish()
    }

    // MARK: - Private Methods

    private func startReceiving() {
        guard let webSocket else { return }

        Task {
            do {
                while connected {
                    let message = try await webSocket.receive()

                    switch message {
                    case let .data(data):
                        guard enqueue(data) else { return }

                    case let .string(text):
                        if let data = text.data(using: .utf8) {
                            guard enqueue(data) else { return }
                        }

                    @unknown default:
                        logger.warning("Unknown WebSocket message type")
                    }
                }
            } catch {
                if connected {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                    connected = false
                    // Preserve the abnormal receive failure so clients recover
                    // on evidence instead of a generic connection closure.
                    terminationEvidence = TransportTermination(
                        reason: .failure(.read("websocket receive failed")),
                        cleanupComplete: false,
                    )
                    messageQueue.finish()
                }
            }
        }
    }

    /// Bounds a remote peer's ingress: oversized frames and an exhausted queued
    /// byte budget both become sticky typed failures instead of unbounded
    /// memory growth.
    private func enqueue(_ data: Data) -> Bool {
        if data.count > maxFrameBytes {
            terminateWithFailure(.frameLimit(maxFrameBytes), message: "WebSocket frame exceeds limit")
            return false
        }
        guard messageQueue.yield(data, byteCount: data.count) else {
            terminateWithFailure(.bufferOverflow(queuedByteBudget), message: "WebSocket receive budget exceeded")
            return false
        }
        return true
    }

    private func terminateWithFailure(_ failure: TransportFailure, message: String) {
        guard connected else { return }
        logger.error("\(message, privacy: .public)")
        connected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        terminationEvidence = TransportTermination(reason: .failure(failure), cleanupComplete: false)
        messageQueue.finish(discard: true)
    }
}

// MARK: - WebSocket Client

/// Convenience wrapper for using WebSocket transport with the ACP Client.
/// The WebSocket transport is injected into the client, so there is exactly one
/// reader of the message stream.
public actor WebSocketClient {
    private let transport: WebSocketTransport
    private let client: Client

    public init(url: URL) {
        transport = WebSocketTransport(url: url)
        client = Client(transport: transport)
    }

    /// Connect to the WebSocket server, start the client ingress, and initialize.
    public func connect(
        capabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
    ) async throws -> InitializeResponse {
        try await transport.connect()
        try await client.start()
        return try await client.initialize(capabilities: capabilities, clientInfo: clientInfo)
    }

    public func close() async {
        _ = await client.shutdown()
    }
}

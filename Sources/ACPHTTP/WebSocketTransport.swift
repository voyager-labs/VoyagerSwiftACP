import ACP
import ACPModel
import Foundation
import os.log

/// Transport implementation using WebSocket for network communication.
/// Works on all Apple platforms (iOS, macOS, tvOS, watchOS).
public actor WebSocketTransport: Transport {
    // MARK: - Properties

    private var webSocket: URLSessionWebSocketTask?
    private let session: URLSession
    private let url: URL
    private let logger: Logger

    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let messageStream: AsyncStream<Data>

    private var connected = false

    // MARK: - Transport Protocol

    nonisolated public var messages: AsyncStream<Data> {
        messageStream
    }

    public var isConnected: Bool {
        connected
    }

    // MARK: - Initialization

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        logger = Logger.forCategory("WebSocketTransport")

        var continuation: AsyncStream<Data>.Continuation!
        messageStream = AsyncStream { cont in
            continuation = cont
        }
        messageContinuation = continuation
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
        messageContinuation?.finish()
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
                        messageContinuation?.yield(data)

                    case let .string(text):
                        if let data = text.data(using: .utf8) {
                            messageContinuation?.yield(data)
                        }

                    @unknown default:
                        logger.warning("Unknown WebSocket message type")
                    }
                }
            } catch {
                if connected {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                    connected = false
                    messageContinuation?.finish()
                }
            }
        }
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

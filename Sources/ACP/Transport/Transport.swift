import ACPModel
import Foundation

/// Protocol defining the transport layer for ACP communication.
/// Implementations handle the low-level message sending and receiving.
public protocol Transport: Sendable {
    /// Send data through the transport. Implementations append the ACP newline framing.
    func send(_ data: Data) async throws

    /// Stream of incoming messages. Each element is one complete wire frame.
    var messages: AsyncStream<Data> { get }

    /// Close the transport connection
    func close() async

    /// Whether the transport is currently connected/running
    var isConnected: Bool { get async }

    /// Terminal evidence for the transport, available once `messages` has finished.
    ///
    /// `nil` means no direct-child termination evidence was confirmed; a `nil` value
    /// must not be interpreted as "the direct child exited cleanly". When `messages`
    /// ends without terminal evidence, callers treat it as a generic connection closure.
    var termination: TransportTermination? { get async }
}

public extension Transport {
    /// Default for transports that do not track direct-child termination evidence.
    var termination: TransportTermination? {
        get async { nil }
    }
}

/// Events emitted by transports for lifecycle management
public enum TransportEvent: Sendable {
    case connected
    case disconnected(Error?)
    case message(Data)
}

/// Configuration for transport behavior.
/// ACP v1 stdio framing defaults: 8 MiB per frame, 64 KiB read chunks,
/// and a 16 MiB budget for queued incoming messages and incomplete frames.
public struct TransportConfiguration: Sendable {
    /// Maximum single frame size in bytes
    public let maxMessageSize: Int

    /// Read buffer size
    public let bufferSize: Int

    /// Maximum bytes queued for a consumer or retained as an incomplete frame.
    /// Exceeding either budget terminates input with an explicit overflow failure.
    public let queuedByteBudget: Int

    public init(maxMessageSize: Int = 8 * 1024 * 1024, bufferSize: Int = 65536) {
        self.init(maxMessageSize: maxMessageSize, bufferSize: bufferSize, queuedByteBudget: 16 * 1024 * 1024)
    }

    public init(
        maxMessageSize: Int = 8 * 1024 * 1024,
        bufferSize: Int = 65536,
        queuedByteBudget: Int,
    ) {
        self.maxMessageSize = maxMessageSize
        self.bufferSize = bufferSize
        self.queuedByteBudget = queuedByteBudget
    }

    public static let `default` = TransportConfiguration()

    /// Rejects non-positive limits. Transports call this at startup.
    public func validated() throws {
        guard maxMessageSize > 0 else {
            throw ClientError.transportFailure(.startup("maxMessageSize must be positive"))
        }
        guard bufferSize > 0 else {
            throw ClientError.transportFailure(.startup("bufferSize must be positive"))
        }
        guard queuedByteBudget > 0 else {
            throw ClientError.transportFailure(.startup("queuedByteBudget must be positive"))
        }
    }
}

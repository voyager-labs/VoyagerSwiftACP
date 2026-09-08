import ACPModel
import Foundation

/// Immutable configuration for a `Client` connection.
public struct ClientConfiguration: Sendable {
    /// Default deadline applied to ordinary requests. `nil` disables the default.
    public let requestTimeout: TimeInterval?
    /// Default deadline applied to `session/prompt` requests. `nil` (the default)
    /// means prompts have no deadline.
    public let promptTimeout: TimeInterval?
    /// Grace period after `session/cancel` before an unanswered prompt turn
    /// forces the connection to shut down.
    public let cancellationGrace: TimeInterval
    /// Byte budget for notifications waiting for the application consumer.
    public let notificationByteBudget: Int
    /// Underlying transport limits.
    public let transport: TransportConfiguration

    public init(
        requestTimeout: TimeInterval? = 30,
        promptTimeout: TimeInterval? = nil,
        cancellationGrace: TimeInterval = 2,
        notificationByteBudget: Int = 16 * 1024 * 1024,
        transport: TransportConfiguration = .default,
    ) {
        self.requestTimeout = requestTimeout
        self.promptTimeout = promptTimeout
        self.cancellationGrace = cancellationGrace
        self.notificationByteBudget = notificationByteBudget
        self.transport = transport
    }

    public static let `default` = ClientConfiguration()
}

/// Lifecycle states of a client connection.
///
/// Transition summary:
/// - `idle → starting → connected` via `launch`/`start`
/// - `connected → initializing → ready` via `initialize`
/// - `initializing → failed` when negotiation fails, times out, is cancelled,
///   or the agent selects an unsupported protocol version (terminal)
/// - any state `→ closing → closed` via `shutdown`
/// - any state `→ failed` on typed transport failure or peer protocol violation (terminal)
public enum ClientConnectionState: Sendable, Equatable {
    case idle
    case starting
    case connected
    case initializing
    case ready
    case closing
    case closed
    case failed
}

/// Per-session lifecycle observed by the client.
public enum SessionState: Sendable, Equatable {
    case idle
    case prompting
    case cancelling
    case closed
}

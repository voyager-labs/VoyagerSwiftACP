import ACPModel
import Foundation

public struct TransportTermination: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// `close()` was called by the local side.
        case explicitClose
        /// The peer's output stream reached EOF while the direct child may still be alive.
        case stdoutEOF
        /// The direct child process exited on its own.
        case processExit(Int32)
        /// A typed transport failure terminated the connection.
        case failure(TransportFailure)
    }

    /// Why the transport ended. Once set, later events do not overwrite it.
    public let reason: Reason
    /// Observed direct-child exit status, when the child was confirmed to have exited.
    public let exitStatus: Int32?
    /// Signal that terminated the direct child, when applicable.
    public let terminationSignal: Int32?
    /// True only when the direct child exit was confirmed and pipes were reaped.
    public let cleanupComplete: Bool

    public init(
        reason: Reason,
        exitStatus: Int32? = nil,
        terminationSignal: Int32? = nil,
        cleanupComplete: Bool,
    ) {
        self.reason = reason
        self.exitStatus = exitStatus
        self.terminationSignal = terminationSignal
        self.cleanupComplete = cleanupComplete
    }

    /// Evidence used when a transport provides no termination tracking at all.
    /// `cleanupComplete` is false because no direct-child exit was confirmed.
    public static func genericClosure() -> TransportTermination {
        TransportTermination(reason: .explicitClose, exitStatus: nil, terminationSignal: nil, cleanupComplete: false)
    }
}

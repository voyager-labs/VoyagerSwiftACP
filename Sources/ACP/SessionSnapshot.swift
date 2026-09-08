import ACPModel
import Foundation

/// Read-only snapshot of a session tracked by the client.
/// The session ID is agent-generated and treated as opaque; the client never
/// derives Voyager run IDs or provider session references from it.
public struct SessionSnapshot: Sendable, Equatable {
    public let sessionId: SessionId
    public let state: SessionState
    public let lastStopReason: StopReason?

    public init(sessionId: SessionId, state: SessionState, lastStopReason: StopReason? = nil) {
        self.sessionId = sessionId
        self.state = state
        self.lastStopReason = lastStopReason
    }
}

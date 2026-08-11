nonisolated public enum EntryCoreTransportPhase: Equatable, Sendable {
    case connect
    case write
    case read
}

nonisolated public enum EntryCoreClientError: Error, Equatable, Sendable {
    case invalidEndpoint
    case daemonUnavailable
    case timedOut(EntryCoreTransportPhase)
    case cancelled
    case transport(EntryCoreTransportPhase)
    case responseTooLarge
    case malformedResponse
    case protocolMismatch
    case requestIDMismatch
    case server(EntryCoreServerErrorCode)
}

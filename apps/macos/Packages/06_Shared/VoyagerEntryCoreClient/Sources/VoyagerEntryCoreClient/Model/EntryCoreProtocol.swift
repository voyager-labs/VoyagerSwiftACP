nonisolated public enum EntryCoreProtocolVersion: Int, Equatable, Sendable {
    case v1 = 1
}

nonisolated public enum EntryCoreMethod: String, CaseIterable, Equatable, Sendable {
    case ping
    case health
    case version
}

nonisolated public struct EntryCorePingResult: Equatable, Sendable {
    public let message: String

    public init() {
        message = "pong"
    }
}

nonisolated public struct EntryCoreHealthResult: Equatable, Sendable {
    public let status: String
    public let state: String

    public init() {
        status = "healthy"
        state = "running"
    }
}

nonisolated public struct EntryCoreVersionResult: Equatable, Sendable {
    public let appVersion: String
    public let protocolVersion: EntryCoreProtocolVersion

    public init(appVersion: String) throws {
        guard !appVersion.isEmpty else {
            throw EntryCoreClientError.protocolMismatch
        }

        self.appVersion = appVersion
        protocolVersion = .v1
    }
}

nonisolated public enum EntryCoreServerErrorCode: String, CaseIterable, Equatable, Sendable {
    case requestTooLarge = "request_too_large"
    case invalidRequest = "invalid_request"
    case unsupportedProtocolVersion = "unsupported_protocol_version"
    case unknownMethod = "unknown_method"
    case internalError = "internal_error"
}

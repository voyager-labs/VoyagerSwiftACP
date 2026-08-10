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

    public init(appVersion: String) throws {
        guard !appVersion.isEmpty else {
            throw EntryCoreClientError.protocolMismatch
        }

        self.appVersion = appVersion
    }
}

nonisolated public enum EntryCoreServerErrorCode: String, CaseIterable, Equatable, Sendable {
    case requestTooLarge = "request_too_large"
    case invalidRequest = "invalid_request"
    case unknownMethod = "unknown_method"
    case internalError = "internal_error"

    var canonicalMessage: String {
        switch self {
        case .requestTooLarge:
            "request is too large"
        case .invalidRequest:
            "request is invalid"
        case .unknownMethod:
            "method is unknown"
        case .internalError:
            "internal error"
        }
    }
}

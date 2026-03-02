import Foundation

public nonisolated enum BetaAccessStatus: String, Equatable, Sendable {
    case active = "Active"
    case notActive = "Not Active"
    case checkFailed = "Check failed"
}

public nonisolated enum BetaAccessReason: Equatable, Sendable {
    case none
    case missingInput
    case missingToken
    case invalidToken
    case invalidRequest
    case invalidCredentials
    case emailMismatch
    case alreadyUsed
    case deviceMismatch
    case deviceIdUnavailable
    case authBackendError
    case networkError
    case invalidGatewayUrl
    case internalError
}

public nonisolated struct BetaAccessVerificationResult: Equatable, Sendable {
    public var status: BetaAccessStatus
    public var reason: BetaAccessReason

    public init(status: BetaAccessStatus, reason: BetaAccessReason = .none) {
        self.status = status
        self.reason = reason
    }
}

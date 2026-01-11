import Foundation

nonisolated enum BetaAccessStatus: String, Equatable, Sendable {
    case active = "Active"
    case notActive = "Not Active"
    case checkFailed = "Check failed"
}

nonisolated enum BetaAccessReason: Equatable, Sendable {
    case none
    case missingInput
    case mismatch
    case tokenAlreadyRegistered
}

nonisolated struct BetaAccessVerificationResult: Equatable, Sendable {
    var status: BetaAccessStatus
    var reason: BetaAccessReason

    init(status: BetaAccessStatus, reason: BetaAccessReason = .none) {
        self.status = status
        self.reason = reason
    }
}

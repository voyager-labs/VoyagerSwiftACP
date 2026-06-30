import Foundation

nonisolated public enum AccessStatus: String, Equatable, Sendable, Codable {
    case coreLicenseActive = "core_license_active"
    case trialActive = "trial_active"
    case internalTestActive = "internal_test_active"
    case none
    case trialExpired = "trial_expired"
    case revoked
    case refunded
    case networkFailure = "network_failure"

    public var isActive: Bool {
        switch self {
        case .coreLicenseActive, .trialActive, .internalTestActive: true
        case .none, .trialExpired, .revoked, .refunded, .networkFailure: false
        }
    }
}

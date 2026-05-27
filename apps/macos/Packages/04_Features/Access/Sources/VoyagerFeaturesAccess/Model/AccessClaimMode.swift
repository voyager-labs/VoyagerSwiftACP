import Foundation

public nonisolated enum AccessClaimMode: String, Equatable, Sendable, Codable {
    case licenseKey = "license_key"
    case betaCode = "beta_code"
}

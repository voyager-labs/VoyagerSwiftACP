import Foundation

public nonisolated enum LicenseAuthClaimMode: String, Equatable, Sendable, Codable {
    case licenseKey = "license_key"
    case betaCode = "beta_code"
}

import Foundation

public struct LicenseAuthEntitlement: Equatable, Sendable, Codable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let coreLicense = LicenseAuthEntitlement(rawValue: "core_license")
    public static let betaTrial = LicenseAuthEntitlement(rawValue: "beta_trial")
    public static let internalTest = LicenseAuthEntitlement(rawValue: "internal_test")
}

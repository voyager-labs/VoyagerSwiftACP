import Foundation

public struct AccessEntitlement: Equatable, Sendable, Codable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let coreLicense = AccessEntitlement(rawValue: "core_license")
    public static let betaTrial = AccessEntitlement(rawValue: "beta_trial")
    public static let internalTest = AccessEntitlement(rawValue: "internal_test")
}

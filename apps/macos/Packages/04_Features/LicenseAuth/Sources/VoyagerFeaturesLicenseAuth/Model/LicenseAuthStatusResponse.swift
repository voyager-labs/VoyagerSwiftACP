import Foundation

public struct LicenseAuthStatusResponse: Equatable, Sendable, Codable {
    public var status: LicenseAuthStatus
    public var expiresAt: Date?
    public var entitlements: [LicenseAuthEntitlement]
    public var message: String?
    public var reasonCode: String?
    public init(
        status: LicenseAuthStatus,
        expiresAt: Date? = nil,
        entitlements: [LicenseAuthEntitlement] = [],
        message: String? = nil,
        reasonCode: String? = nil,
    ) {
        self.status = status
        self.expiresAt = expiresAt
        self.entitlements = entitlements
        self.message = message
        self.reasonCode = reasonCode
    }
}

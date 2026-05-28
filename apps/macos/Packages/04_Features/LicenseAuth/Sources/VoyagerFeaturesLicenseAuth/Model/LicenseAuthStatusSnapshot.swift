import Foundation

public struct LicenseAuthStatusSnapshot: Equatable, Sendable, Codable {
    public var status: LicenseAuthStatus
    public var expiresAt: Date?
    public var entitlements: [LicenseAuthEntitlement]
    public var fetchedAt: Date
    public init(
        status: LicenseAuthStatus,
        expiresAt: Date? = nil,
        entitlements: [LicenseAuthEntitlement] = [],
        fetchedAt: Date = Date(),
    ) {
        self.status = status
        self.expiresAt = expiresAt
        self.entitlements = entitlements
        self.fetchedAt = fetchedAt
    }

    public var isActive: Bool { status.isActive }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

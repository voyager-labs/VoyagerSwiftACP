import Foundation

public struct AccessStatusSnapshot: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var expiresAt: Date?
    public var entitlements: [AccessEntitlement]
    public var fetchedAt: Date
    public init(
        status: AccessStatus,
        expiresAt: Date? = nil,
        entitlements: [AccessEntitlement] = [],
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

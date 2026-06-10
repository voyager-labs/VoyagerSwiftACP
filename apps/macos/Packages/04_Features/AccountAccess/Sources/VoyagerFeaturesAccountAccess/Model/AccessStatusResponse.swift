import Foundation

public struct AccessStatusResponse: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var expiresAt: Date?
    public var entitlements: [AccessEntitlement]
    public var message: String?
    public var reasonCode: String?
    public init(
        status: AccessStatus,
        expiresAt: Date? = nil,
        entitlements: [AccessEntitlement] = [],
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

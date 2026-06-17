import Foundation

public struct AccessStatusResponse: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var expiresAt: Date?
    public var entitlements: [AccessEntitlement]
    public var message: String?
    public var reasonCode: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
        case entitlements
        case message
        case reasonCode = "reason_code"
    }

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

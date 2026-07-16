import Foundation

public struct AccountSession: Equatable, Sendable, Codable {
    public var accessToken: String
    public var refreshToken: String?
    public var status: AccessStatus
    public var expiresAt: Date?
    public var sessionBindingID: UUID

    public init(
        accessToken: String,
        status: AccessStatus,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        sessionBindingID: UUID = UUID(),
    ) {
        self.accessToken = accessToken
        self.status = status
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.sessionBindingID = sessionBindingID
    }
}

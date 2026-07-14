import Foundation

public struct AccountSession: Equatable, Sendable, Codable {
    public var accessToken: String
    public var refreshToken: String?
    public var status: AccessStatus
    public var expiresAt: Date?

    public init(
        accessToken: String,
        status: AccessStatus,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
    ) {
        self.accessToken = accessToken
        self.status = status
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

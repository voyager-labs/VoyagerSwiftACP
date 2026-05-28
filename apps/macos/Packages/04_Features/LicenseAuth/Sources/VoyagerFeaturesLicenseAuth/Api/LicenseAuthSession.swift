import Foundation

public struct LicenseAuthSession: Equatable, Sendable, Codable {
    public var accessToken: String
    public var refreshToken: String?
    public var status: LicenseAuthStatus
    public var expiresAt: Date?

    public init(
        accessToken: String,
        status: LicenseAuthStatus,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
    ) {
        self.accessToken = accessToken
        self.status = status
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

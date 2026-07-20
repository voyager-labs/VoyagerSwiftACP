import Foundation

/// `~/.voyager/account_tokens.json`에 저장되는 account token payload의 Codable 모델.
/// in-memory 전용 `status` 필드는 포함하지 않는다 (ADR 0001).
public struct AccountTokensFile: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let updatedAtMs: Int64
    public let accessToken: String
    public let accessTokenExpiresAtMs: Int64
    public let accessTokenExpiresIn: Int64
    public let refreshToken: String
    public let refreshTokenExpiresAtMs: Int64
    public let sessionBindingID: UUID?

    public init(
        schemaVersion: Int = AccountTokensFile.currentSchemaVersion,
        updatedAtMs: Int64,
        accessToken: String,
        accessTokenExpiresAtMs: Int64,
        accessTokenExpiresIn: Int64,
        refreshToken: String,
        refreshTokenExpiresAtMs: Int64,
        sessionBindingID: UUID? = UUID(),
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.accessToken = accessToken
        self.accessTokenExpiresAtMs = accessTokenExpiresAtMs
        self.accessTokenExpiresIn = accessTokenExpiresIn
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAtMs = refreshTokenExpiresAtMs
        self.sessionBindingID = sessionBindingID
    }

    /// raw token을 log/analytics에 노출하지 않도록 마스킹
    public func redacted() -> AccountTokensFile {
        AccountTokensFile(
            schemaVersion: schemaVersion,
            updatedAtMs: updatedAtMs,
            accessToken: "***REDACTED***",
            accessTokenExpiresAtMs: accessTokenExpiresAtMs,
            accessTokenExpiresIn: accessTokenExpiresIn,
            refreshToken: "***REDACTED***",
            refreshTokenExpiresAtMs: refreshTokenExpiresAtMs,
            sessionBindingID: sessionBindingID,
        )
    }
}

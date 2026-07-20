import Foundation

// MARK: - extracted from AccountAccessClient.swift:143

/// POST /auth/token/refresh 성공 응답 디코딩 구조.
/// exchange 성공 응답과 동일한 { ok, session } 스키마를 사용한다.
struct RefreshSuccessResponse: Decodable {
    let ok: Bool
    let session: RefreshSessionPayload?
}

struct RefreshSessionPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

import Foundation

/// AccountTokensFile ↔ AccountSession 변환 mapper.
/// status 필드는 in-memory only (ADR 0001)이므로 파일에 저장하지 않는다.
enum AccountTokenSessionMapper {
    /// AccountTokensFile → AccountSession 변환.
    /// accessToken이 빈 문자열이면 nil 반환.
    static func tokensFileToSession(_ file: AccountTokensFile) -> AccountSession? {
        guard !file.accessToken.isEmpty, let sessionBindingID = file.sessionBindingID else { return nil }

        let expiresAt = Date(timeIntervalSince1970: TimeInterval(file.accessTokenExpiresAtMs) / 1000)
        return AccountSession(
            accessToken: file.accessToken,
            status: .none,
            refreshToken: file.refreshToken,
            expiresAt: expiresAt,
            sessionBindingID: sessionBindingID,
        )
    }

    /// AccountSession → AccountTokensFile 변환.
    /// exchangeAppHandoff(T5) 성공 후 토큰 저장에 사용.
    /// refreshToken이 없으면 nil 반환 (영구 저장 불가).
    static func sessionToTokensFile(_ session: AccountSession, now: Date) -> AccountTokensFile? {
        guard let refreshToken = session.refreshToken else { return nil }

        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let expiresAtMs = session.expiresAt
            .map { Int64($0.timeIntervalSince1970 * 1000) }
            ?? (nowMs + 900_000)
        let expiresIn = max(0, expiresAtMs - nowMs)

        return AccountTokensFile(
            updatedAtMs: nowMs,
            accessToken: session.accessToken,
            accessTokenExpiresAtMs: expiresAtMs,
            accessTokenExpiresIn: expiresIn,
            refreshToken: refreshToken,
            refreshTokenExpiresAtMs: expiresAtMs + 2_592_000_000,
            sessionBindingID: session.sessionBindingID,
        )
    }
}

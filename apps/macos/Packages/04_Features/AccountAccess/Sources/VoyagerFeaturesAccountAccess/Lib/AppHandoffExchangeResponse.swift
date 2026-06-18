import Foundation

// MARK: - extracted from AppHandoffExchangeClient.swift:83

/// VOY-334 exchange 성공 응답: `{ ok, session, user }`
struct ExchangeSuccessResponse: Decodable {
    let ok: Bool
    let session: ExchangeSessionPayload?
    let user: ExchangeUserPayload?
}

struct ExchangeSessionPayload: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Double?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct ExchangeUserPayload: Decodable {
    let id: String?
}

// MARK: - extracted from AppHandoffExchangeClient.swift:116

func decodeExchangeSuccessResponse(_ data: Data) throws -> ExchangeSuccessResponse {
    do {
        return try JSONDecoder().decode(ExchangeSuccessResponse.self, from: data)
    } catch {
        throw AppHandoffExchangeError.decodingFailure
    }
}

func sessionFromExchangeResponse(_ response: ExchangeSuccessResponse) throws -> AccountSession {
    guard let sessionPayload = response.session,
          let accessToken = sessionPayload.accessToken, !accessToken.isEmpty
    else {
        throw AppHandoffExchangeError.decodingFailure
    }

    let expiresAt: Date? = sessionPayload.expiresAt.map { Date(timeIntervalSince1970: $0) }

    return AccountSession(
        accessToken: accessToken,
        status: .coreLicenseActive,
        refreshToken: sessionPayload.refreshToken,
        expiresAt: expiresAt,
    )
}

func extractErrorCode(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json["code"] as? String
}

func throwMappedExchangeError(_ code: String?) throws -> AccountSession {
    switch code {
    case "ticket_already_used": throw AppHandoffExchangeError.ticketAlreadyUsed
    case "state_mismatch": throw AppHandoffExchangeError.stateMismatch
    case "invalid_or_expired_ticket": throw AppHandoffExchangeError.invalidOrExpiredTicket
    case "account_mismatch": throw AppHandoffExchangeError.accountMismatch
    case "supabase_session_issuance_failed": throw AppHandoffExchangeError.sessionIssuanceFailed
    default: throw AppHandoffExchangeError.unknownGatewayCode(code ?? "unknown")
    }
}

import ComposableArchitecture
import Foundation

/// `/auth/app-handoff/exchange` 호출을 담당하는 의존성.
/// 티켓·state·context로 서버에 세션 교환을 요청한다.
/// 성공 시 `AccountSession`을 반환한다.
/// 토큰·세션 정보는 로깅하지 않는다.
public struct AppHandoffExchangeClient: Sendable {
    public var exchange: @Sendable (_ ticket: String, _ state: String, _ context: AppHandoffContext) async throws
        -> AccountSession

    public nonisolated init(
        exchange: @escaping @Sendable (_ ticket: String, _ state: String, _ context: AppHandoffContext) async throws
            -> AccountSession,
    ) {
        self.exchange = exchange
    }
}

extension AppHandoffExchangeClient: DependencyKey {
    public nonisolated static var liveValue: AppHandoffExchangeClient {
        AppHandoffExchangeClient { ticket, state, context in
            guard let gatewayURLString = ProcessInfo.processInfo.environment["PUBLIC_GATEWAY_URL"],
                  !gatewayURLString.isEmpty
            else {
                throw AppHandoffExchangeError.networkFailure
            }

            let builder = AppHandoffURLBuilder(
                webBaseURL: ProcessInfo.processInfo.environment["PUBLIC_WEB_BASE_URL"] ?? "",
                gatewayURL: gatewayURLString,
            )

            guard let exchangeURL = builder.exchangeURL else {
                throw AppHandoffExchangeError.networkFailure
            }

            let requestBody: [String: String] = [
                "ticket": ticket,
                "state": state,
                "context": context.rawValue,
            ]

            var request = URLRequest(url: exchangeURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw AppHandoffExchangeError.networkFailure
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppHandoffExchangeError.networkFailure
            }

            if httpResponse.statusCode == 200 {
                return try AppHandoffExchangeClient.decodeSession(fromExchangeSuccessData: data)
            }

            // 에러 응답은 code만 추출 (토큰/본문 전체 로깅 금지)
            let errorCode = extractErrorCode(from: data)
            return try throwMappedExchangeError(errorCode)
        }
    }

    public nonisolated static var testValue: AppHandoffExchangeClient {
        AppHandoffExchangeClient { _, _, _ in throw AppHandoffExchangeError.networkFailure }
    }

    public nonisolated static var previewValue: AppHandoffExchangeClient {
        AppHandoffExchangeClient { _, _, _ in
            AccountSession(accessToken: "preview-token", status: .coreLicenseActive)
        }
    }
}

// MARK: - Exchange Response Decoding

/// VOY-334 exchange 성공 응답: `{ ok, session, user }`
private struct ExchangeSuccessResponse: Decodable {
    let ok: Bool
    let session: ExchangeSessionPayload?
    let user: ExchangeUserPayload?
}

private struct ExchangeSessionPayload: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Double?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

private struct ExchangeUserPayload: Decodable {
    let id: String?
}

extension AppHandoffExchangeClient {
    nonisolated static func decodeSession(fromExchangeSuccessData data: Data) throws -> AccountSession {
        let exchangeResponse = try decodeExchangeSuccessResponse(data)
        guard exchangeResponse.ok else {
            throw AppHandoffExchangeError.decodingFailure
        }
        return try sessionFromExchangeResponse(exchangeResponse)
    }
}

private func decodeExchangeSuccessResponse(_ data: Data) throws -> ExchangeSuccessResponse {
    do {
        return try JSONDecoder().decode(ExchangeSuccessResponse.self, from: data)
    } catch {
        throw AppHandoffExchangeError.decodingFailure
    }
}

private func sessionFromExchangeResponse(_ response: ExchangeSuccessResponse) throws -> AccountSession {
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

private func extractErrorCode(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json["code"] as? String
}

private func throwMappedExchangeError(_ code: String?) throws -> AccountSession {
    switch code {
    case "ticket_already_used": throw AppHandoffExchangeError.ticketAlreadyUsed
    case "state_mismatch": throw AppHandoffExchangeError.stateMismatch
    case "invalid_or_expired_ticket": throw AppHandoffExchangeError.invalidOrExpiredTicket
    case "account_mismatch": throw AppHandoffExchangeError.accountMismatch
    case "supabase_session_issuance_failed": throw AppHandoffExchangeError.sessionIssuanceFailed
    default: throw AppHandoffExchangeError.unknownGatewayCode(code ?? "unknown")
    }
}

public extension DependencyValues {
    nonisolated var appHandoffExchangeClient: AppHandoffExchangeClient {
        get { self[AppHandoffExchangeClient.self] }
        set { self[AppHandoffExchangeClient.self] = newValue }
    }
}

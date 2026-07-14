import Foundation

/// Deep link 콜백(`voyager://auth/callback?...`)에서 파싱한 인증 handoff 결과.
/// 민감 파라미터(access_token, refresh_token, code)가 포함된 URL은 거부한다.
struct AppHandoffCallback: Equatable {
    let ticket: String
    let state: String
    let context: AppHandoffContext

    /// URL에서 ticket, state, context를 추출해 콜백을 생성한다.
    /// - Parameters:
    ///   - url: `voyager://auth/callback?ticket=...&state=...&context=onboarding` 형식의 deep link
    ///   - expectedScheme: 허용할 callback scheme
    /// - Returns: scheme/host/path가 일치하고, 필수 파라미터가 모두 존재하며,
    ///   context가 allowlist에 포함되고, 민감 파라미터가 없으면 생성된 콜백. 그 외에는 nil.
    init?(url: URL, expectedScheme: String) {
        guard url.scheme == expectedScheme,
              url.host == "auth",
              url.path == "/callback"
        else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else { return nil }

        let sensitiveKeys = ["access_token", "refresh_token", "code"]
        for item in queryItems where sensitiveKeys.contains(item.name) {
            return nil
        }

        guard let ticketValue = queryItems.first(where: { $0.name == "ticket" })?.value,
              !ticketValue.isEmpty,
              let stateValue = queryItems.first(where: { $0.name == "state" })?.value,
              !stateValue.isEmpty,
              let contextRaw = queryItems.first(where: { $0.name == "context" })?.value,
              let contextValue = AppHandoffContext(rawValue: contextRaw),
              AppHandoffContext.allowed.contains(contextValue)
        else { return nil }

        ticket = ticketValue
        state = stateValue
        context = contextValue
    }
}

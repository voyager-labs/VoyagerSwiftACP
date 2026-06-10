import Foundation

/// 인증 handoff URL을 생성하는 빌더.
/// 웹 로그인 URL과 게이트웨이 exchange URL을 환경 변수 기반으로 구성한다.
public struct AppHandoffURLBuilder: Sendable {
    private let webBaseURL: String
    private let gatewayURL: String

    public init(webBaseURL: String, gatewayURL: String) {
        self.webBaseURL = webBaseURL
        self.gatewayURL = gatewayURL
    }

    /// `{webBaseURL}/auth/login?mode=app&state={state}&context={context.rawValue}` 형식의 로그인 URL을 생성한다.
    /// webBaseURL이 유효하지 않으면 nil을 반환한다.
    public func buildLoginURL(state: String, context: AppHandoffContext) -> URL? {
        guard let base = URL(string: webBaseURL) else { return nil }
        var components = URLComponents(url: base.appendingPathComponent("auth/login"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "mode", value: "app"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "context", value: context.rawValue),
        ]
        return components?.url
    }

    /// `{gatewayURL}/auth/app-handoff/exchange` URL.
    /// gatewayURL이 유효하지 않으면 nil을 반환한다.
    public var exchangeURL: URL? {
        guard let base = URL(string: gatewayURL) else { return nil }
        return base.appendingPathComponent("auth/app-handoff/exchange")
    }
}

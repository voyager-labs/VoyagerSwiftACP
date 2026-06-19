import Foundation

// MARK: - Deep Link Result

/// `ExternalFileURLParser.parse(_:)`의 반환 타입
public enum DeepLinkParserResult: Equatable, Sendable {
    /// 정상 파싱된 Deep Link 요청
    case request(DeepLinkRequest)
    /// 인증 콜백 (`voyager://auth/callback`, ACC 라우팅용)
    case authCallback(URL)
    /// 파싱 오류
    case error(DeepLinkParserError)
}

// MARK: - Deep Link Request

/// 파싱된 Deep Link 요청 정보
public struct DeepLinkRequest: Equatable, Sendable {
    public let url: URL
    public let mode: DeepLinkMode
    public let source: DeepLinkSource

    public init(url: URL, mode: DeepLinkMode, source: DeepLinkSource) {
        self.url = url
        self.mode = mode
        self.source = source
    }
}

// MARK: - Deep Link Mode

/// 파일 열기 모드
public enum DeepLinkMode: String, Equatable, Sendable {
    /// 폴더 열기 (기본값)
    case open
    /// 파일 위치 표시 (부모 폴더 열기 + 파일 선택 focus)
    case reveal
}

// MARK: - Deep Link Source

/// Deep Link 출처
public enum DeepLinkSource: Equatable, Sendable {
    /// 외부 Deep Link URL (`voyager://open`)
    case deepLink
}

// MARK: - Parser Error

/// Deep Link URL 파싱 오류
public enum DeepLinkParserError: Error, Equatable, Sendable {
    /// 올바르지 않은 scheme 또는 host
    case invalidSchemeOrHost
    /// `url` 파라미터 누락
    case missingURLParameter
    /// percent-encoding 오류 또는 유효하지 않은 URL 문자열
    case invalidPercentEncoding
    /// `file://` URL이 아님
    case unsupportedURLScheme
}

// MARK: - ExternalFileURLParser

/// `voyager://open` Deep Link URL을 파싱하는 순수 함수 모음
public enum ExternalFileURLParser {
    /// 주어진 URL을 파싱하여 `DeepLinkParserResult`를 반환한다.
    ///
    /// - Parameter url: 외부에서 수신한 `voyager://` Deep Link URL
    /// - Returns: 파싱 결과 (`.request` / `.authCallback` / `.error`)
    public static func parse(_ url: URL) -> DeepLinkParserResult {
        // scheme 검증
        guard url.scheme?.lowercased() == "voyager" else {
            return .error(.invalidSchemeOrHost)
        }

        let host = url.host?.lowercased()
        let path = url.path

        // auth/callback 식별 (ACC 라우팅용, FMW-003가 가로채지 않음)
        if host == "auth", path.lowercased() == "/callback" {
            return .authCallback(url)
        }

        // open host 검증 (path는 비어있거나 "/"만 허용)
        guard host == "open", path.isEmpty || path == "/" else {
            return .error(.invalidSchemeOrHost)
        }

        // query items 파싱
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let percentEncodedItems = components.percentEncodedQueryItems
        else {
            return .error(.missingURLParameter)
        }

        // url 파라미터 추출 (percent-encoded raw value 사용)
        guard let rawURLValue = percentEncodedItems.first(where: { $0.name == "url" })?.value else {
            return .error(.missingURLParameter)
        }

        // percent-decode 검증
        guard let decodedString = rawURLValue.removingPercentEncoding,
              let fileURL = URL(string: decodedString)
        else {
            return .error(.invalidPercentEncoding)
        }

        // file:// scheme 검증
        guard fileURL.scheme?.lowercased() == "file" else {
            return .error(.unsupportedURLScheme)
        }

        // mode 파라미터 추출 (기본값 open)
        let mode: DeepLinkMode = if let rawModeValue = percentEncodedItems.first(where: { $0.name == "mode" })?.value,
                                    rawModeValue.lowercased() == "reveal"
        {
            .reveal
        } else {
            .open
        }

        return .request(DeepLinkRequest(url: fileURL, mode: mode, source: .deepLink))
    }
}

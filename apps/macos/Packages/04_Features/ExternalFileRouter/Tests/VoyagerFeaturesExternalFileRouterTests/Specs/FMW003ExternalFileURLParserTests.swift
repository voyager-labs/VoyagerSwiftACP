@testable import VoyagerFeaturesExternalFileRouter
import XCTest

final class FMW003ExternalFileURLParserTests: XCTestCase {
    // MARK: - Happy path

    /// 유효한 폴더 URL + open mode (기본값)이 정상 파싱되는지 검증
    func testValidFolderURLParsesWithOpenMode() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .request(request) = result else {
            return XCTFail("Expected .request, got \(result)")
        }
        XCTAssertEqual(request.url.path, "/Users/test")
        XCTAssertEqual(request.mode, .open)
        XCTAssertEqual(request.source, .deepLink)
    }

    /// mode=reveal 파라미터가 포함된 Deep Link에서 reveal mode가 설정되는지 검증
    func testModeRevealParameter() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest&mode=reveal"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .request(request) = result else {
            return XCTFail("Expected .request, got \(result)")
        }
        XCTAssertEqual(request.mode, .reveal)
    }

    /// mode 파라미터가 없으면 기본값이 open인지 검증
    func testDefaultModeIsOpenWhenModeParameterMissing() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .request(request) = result else {
            return XCTFail("Expected .request, got \(result)")
        }
        XCTAssertEqual(request.mode, .open)
    }

    // MARK: - 실패 케이스

    /// url 파라미터가 없으면 일반 앱 열기 fallback으로 파싱되는지 검증
    func testBareOpenURLReturnsOpenAppFallback() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open"))
        let result = ExternalFileURLParser.parse(url)

        XCTAssertEqual(result, .openAppFallback(url))
    }

    /// url 파라미터가 있지만 값이 비어 있으면 invalidPercentEncoding 에러가 반환되는지 검증
    func testEmptyURLParameterReturnsError() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url="))
        let result = ExternalFileURLParser.parse(url)

        XCTAssertEqual(result, .error(.invalidPercentEncoding))
    }

    /// https 등 file://가 아닌 URL이 url 파라미터로 전달되면 unsupportedURLScheme 에러가 반환되는지 검증
    func testNonFileURLReturnsError() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=https%3A%2F%2Fexample.com"))
        let result = ExternalFileURLParser.parse(url)

        XCTAssertEqual(result, .error(.unsupportedURLScheme))
    }

    /// 알 수 없는 voyager host/path가 전달되면 invalidSchemeOrHost 에러가 반환되는지 검증
    func testUnknownHostPathReturnsError() throws {
        let url = try XCTUnwrap(URL(string: "voyager://unknown/path"))
        let result = ExternalFileURLParser.parse(url)

        XCTAssertEqual(result, .error(.invalidSchemeOrHost))
    }

    // MARK: - auth/callback 식별

    /// voyager://auth/callback URL이 authCallback으로 식별되는지 검증
    func testAuthCallbackIdentified() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc&state=xyz"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .authCallback(callbackURL) = result else {
            return XCTFail("Expected .authCallback, got \(result)")
        }
        XCTAssertEqual(callbackURL, url)
    }

    // MARK: - mode edge cases

    /// mode 값이 소문자 reveal이 아닌 대문자 REVEAL도 정상 처리되는지 검증 (case-insensitive)
    func testModeRevealCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest&mode=REVEAL"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .request(request) = result else {
            return XCTFail("Expected .request, got \(result)")
        }
        XCTAssertEqual(request.mode, .reveal)
    }

    /// 알 수 없는 mode 값은 open으로 기본 처리되는지 검증
    func testUnknownModeDefaultsToOpen() throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2FUsers%2Ftest&mode=unknown"))
        let result = ExternalFileURLParser.parse(url)

        guard case let .request(request) = result else {
            return XCTFail("Expected .request, got \(result)")
        }
        XCTAssertEqual(request.mode, .open)
    }
}

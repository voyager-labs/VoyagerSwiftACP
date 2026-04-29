import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class LocalOAuthHTTPServerTests: XCTestCase {
    func testParseQuery_simpleParams() {
        let result = LocalOAuthHTTPServer.parseQuery("code=abc123&state=xyz")
        XCTAssertEqual(result["code"], "abc123")
        XCTAssertEqual(result["state"], "xyz")
    }

    func testParseQuery_errorParams() {
        let result = LocalOAuthHTTPServer.parseQuery("error=access_denied&error_description=User+denied")
        XCTAssertEqual(result["error"], "access_denied")
        XCTAssertEqual(result["error_description"], "User denied")
    }

    func testParseQuery_emptyString() {
        let result = LocalOAuthHTTPServer.parseQuery("")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseQuery_singleParamNoValue_ignored() {
        let result = LocalOAuthHTTPServer.parseQuery("code")
        XCTAssertTrue(result.isEmpty)
    }

    func testHtmlPage_containsTitle() {
        let html = LocalOAuthHTTPServer.htmlPage(title: "Test Title", body: "Test Body")
        XCTAssertTrue(html.contains("Test Title"))
        XCTAssertTrue(html.contains("Test Body"))
    }
}

import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class LocalOAuthHTTPServerTests: XCTestCase {
    func testCancelUnblocksPendingCallbackWait() async throws {
        let server = LocalOAuthHTTPServer(port: 0)
        let waitTask = Task {
            try await server.waitForCallback()
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        server.cancel()

        do {
            _ = try await waitTask.value
            XCTFail("Expected cancellation to unblock the pending OAuth callback wait")
        } catch OAuthCallbackError.cancelled {
        } catch {
            XCTFail("Expected OAuthCallbackError.cancelled, got \(error)")
        }
    }

    func testCancelBeforeCallbackWaitFailsImmediately() async throws {
        let server = LocalOAuthHTTPServer(port: 0)
        server.cancel()

        do {
            _ = try await server.waitForCallback()
            XCTFail("Expected pre-cancelled OAuth callback wait to fail immediately")
        } catch OAuthCallbackError.cancelled {
        } catch {
            XCTFail("Expected OAuthCallbackError.cancelled, got \(error)")
        }
    }

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

    func testHtmlPage_escapesTitleAndBody() {
        let html = LocalOAuthHTTPServer.htmlPage(
            title: "<Auth & \"Title\">",
            body: "Denied <script>alert(1)</script> & \"quoted\"",
        )

        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<Auth"))
        XCTAssertTrue(html.contains("&lt;Auth &amp; &quot;Title&quot;&gt;"))
        XCTAssertTrue(html.contains("Denied &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quoted&quot;"))
    }

    func testHtmlPage_containsTitle() {
        let html = LocalOAuthHTTPServer.htmlPage(title: "Test Title", body: "Test Body")
        XCTAssertTrue(html.contains("Test Title"))
        XCTAssertTrue(html.contains("Test Body"))
    }
}

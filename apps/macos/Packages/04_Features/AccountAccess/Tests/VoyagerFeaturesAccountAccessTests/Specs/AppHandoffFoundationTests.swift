@testable import VoyagerFeaturesAccountAccess
import XCTest

final class AppHandoffCallbackTests: XCTestCase {
    // MARK: - 유효 URL 파싱

    func testParsesValidCallbackURL() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc123&state=xyz789&context=onboarding"))
        let callback = AppHandoffCallback(url: url)
        XCTAssertNotNil(callback)
        XCTAssertEqual(callback?.ticket, "abc123")
        XCTAssertEqual(callback?.state, "xyz789")
        XCTAssertEqual(callback?.context, .onboarding)
    }

    // MARK: - 거부: 민감 파라미터 포함

    func testRejectsURLWithAccessToken() throws {
        let url = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=abc&state=xyz&context=onboarding&access_token=secret"),
        )
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsURLWithRefreshToken() throws {
        let url = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=abc&state=xyz&context=onboarding&refresh_token=secret"),
        )
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsURLWithCode() throws {
        let url = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=abc&state=xyz&context=onboarding&code=oauth_code"),
        )
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    // MARK: - 거부: 잘못된 scheme/host/path

    func testRejectsWrongScheme() throws {
        let url = try XCTUnwrap(URL(string: "https://auth/callback?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsWrongHost() throws {
        let url = try XCTUnwrap(URL(string: "voyager://other/callback?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsWrongPath() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/other?ticket=abc&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    // MARK: - 거부: 필수 파라미터 누락

    func testRejectsMissingTicket() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsMissingState() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsMissingContext() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&state=xyz"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsEmptyTicket() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=&state=xyz&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    func testRejectsEmptyState() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&state=&context=onboarding"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }

    // MARK: - 거부: allowlist에 없는 context

    func testRejectsUnknownContext() throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=abc&state=xyz&context=malicious"))
        XCTAssertNil(AppHandoffCallback(url: url))
    }
}

final class AppHandoffURLBuilderTests: XCTestCase {
    private func makeBuilder(
        webBase: String = "http://localhost:3000",
        gateway: String = "http://localhost:8787",
    ) -> AppHandoffURLBuilder {
        AppHandoffURLBuilder(webBaseURL: webBase, gatewayURL: gateway)
    }

    func testBuildLoginURLConstructsCorrectURL() throws {
        let builder = makeBuilder()
        let url = try XCTUnwrap(builder.buildLoginURL(state: "test-state-123", context: .onboarding))

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "http")
        XCTAssertEqual(components.host, "localhost")
        XCTAssertEqual(components.port, 3000)
        XCTAssertEqual(components.path, "/auth/login")

        let queryItems = try XCTUnwrap(components.queryItems)
        let queryDict = [String: String](uniqueKeysWithValues: queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        XCTAssertEqual(queryDict["mode"], "app")
        XCTAssertEqual(queryDict["state"], "test-state-123")
        XCTAssertEqual(queryDict["context"], "onboarding")
    }

    func testBuildLoginURLReturnsNilForInvalidBaseURL() {
        let builder = makeBuilder(webBase: "not a url :::", gateway: "http://localhost:8787")
        XCTAssertNil(builder.buildLoginURL(state: "test", context: .onboarding))
    }

    func testExchangeURLConstructsCorrectURL() {
        let builder = makeBuilder()
        let url = builder.exchangeURL
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:8787/auth/app-handoff/exchange")
    }

    func testExchangeURLReturnsNilForEmptyGatewayURL() {
        let builder = makeBuilder(webBase: "http://localhost:3000", gateway: "")
        XCTAssertNil(builder.exchangeURL)
    }
}

final class AppHandoffStateGeneratorTests: XCTestCase {
    private func makeValidStatePattern() throws -> NSRegularExpression {
        try NSRegularExpression(pattern: "^[A-Za-z0-9._~-]{1,256}$")
    }

    func testGenerateProducesValidStateString() throws {
        let state = AppHandoffStateGenerator.generate()
        let range = NSRange(location: 0, length: state.utf16.count)
        let validStatePattern = try makeValidStatePattern()
        let match = validStatePattern.firstMatch(in: state, range: range)
        XCTAssertNotNil(match, "Generated state does not match URL-safe pattern: \(state)")
    }

    func testGenerateProducesMinimum32Characters() {
        let state = AppHandoffStateGenerator.generate()
        XCTAssertGreaterThanOrEqual(state.count, 32, "State should be at least 32 characters, got \(state.count)")
    }

    func testGenerateProducesUniqueValues() {
        let states = (0 ..< 20).map { _ in AppHandoffStateGenerator.generate() }
        let uniqueStates = Set(states)
        XCTAssertEqual(states.count, uniqueStates.count, "Generated states should be unique")
    }
}

final class AppHandoffStateStoreTests: XCTestCase {
    private var store: AppHandoffStateStore!

    override func setUp() {
        super.setUp()
        store = AppHandoffStateStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testStoreAndRetrieveMatchingState() async {
        let pending = PendingAppHandoff(
            state: "test-state",
            context: .onboarding,
            createdAt: Date(),
        )
        await store.store(pending)
        let retrieved = await store.retrieveAndClear(expectedState: "test-state")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.state, "test-state")
        XCTAssertEqual(retrieved?.context, .onboarding)
    }

    func testRetrieveAndClearRemovesState() async {
        let pending = PendingAppHandoff(
            state: "test-state",
            context: .onboarding,
            createdAt: Date(),
        )
        await store.store(pending)
        _ = await store.retrieveAndClear(expectedState: "test-state")
        let secondRetrieve = await store.retrieveAndClear(expectedState: "test-state")
        XCTAssertNil(secondRetrieve, "State should be cleared after first retrieval")
    }

    func testRetrieveRejectsMismatchedState() async {
        let pending = PendingAppHandoff(
            state: "correct-state",
            context: .onboarding,
            createdAt: Date(),
        )
        await store.store(pending)
        let retrieved = await store.retrieveAndClear(expectedState: "wrong-state")
        XCTAssertNil(retrieved, "Mismatched state should return nil")
    }

    func testClearRemovesState() async {
        let pending = PendingAppHandoff(
            state: "test-state",
            context: .onboarding,
            createdAt: Date(),
        )
        await store.store(pending)
        await store.clear()
        let retrieved = await store.retrieveAndClear(expectedState: "test-state")
        XCTAssertNil(retrieved, "State should be nil after clear")
    }
}

final class AppHandoffContextTests: XCTestCase {
    func testAllowedContainsOnlyOnboarding() {
        XCTAssertEqual(AppHandoffContext.allowed, [.onboarding])
    }

    func testRawValue() {
        XCTAssertEqual(AppHandoffContext.onboarding.rawValue, "onboarding")
    }
}

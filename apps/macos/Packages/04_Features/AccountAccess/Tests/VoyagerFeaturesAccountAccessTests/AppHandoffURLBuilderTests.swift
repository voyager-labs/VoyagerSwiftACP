// swiftlint:disable force_unwrapping

@testable import VoyagerFeaturesAccountAccess
import XCTest

final class AppHandoffURLBuilderTests: XCTestCase {
    private let builder = AppHandoffURLBuilder(
        webBaseURL: "https://example.com",
        gatewayURL: "https://gw.example.com",
    )

    /// app_target=voyager가 URL에 포함되는지 검증한다.
    func testBuildLoginURLIncludesAppTargetForVoyager() throws {
        let url = try XCTUnwrap(builder.buildLoginURL(state: "abc", context: .onboarding, appTarget: .voyager))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "voyager")
    }

    /// app_target=onboarding_host가 URL에 포함되는지 검증한다.
    func testBuildLoginURLIncludesAppTargetForOnboardingHost() throws {
        let url = try XCTUnwrap(builder.buildLoginURL(state: "abc", context: .onboarding, appTarget: .onboardingHost))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "onboarding_host")
    }

    /// 기존 query(mode, state, context)가 app_target 추가 후에도 유지되는지 검증한다.
    func testBuildLoginURLPreservesExistingQueries() throws {
        let url = try XCTUnwrap(builder.buildLoginURL(state: "abc", context: .onboarding, appTarget: .voyager))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)

        XCTAssertEqual(queryItems.first(where: { $0.name == "mode" })?.value, "app")
        XCTAssertEqual(queryItems.first(where: { $0.name == "state" })?.value, "abc")
        XCTAssertEqual(queryItems.first(where: { $0.name == "context" })?.value, "onboarding")
        XCTAssertEqual(queryItems.first(where: { $0.name == "app_target" })?.value, "voyager")
    }

    /// appTarget을 생략하면 기본값 .voyager가 사용되는지 검증한다.
    func testBuildLoginURLDefaultAppTargetIsVoyager() throws {
        let url = try XCTUnwrap(builder.buildLoginURL(state: "abc", context: .onboarding))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let appTarget = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "app_target" })?.value)
        XCTAssertEqual(appTarget, "voyager")
    }
}

// swiftlint:enable force_unwrapping

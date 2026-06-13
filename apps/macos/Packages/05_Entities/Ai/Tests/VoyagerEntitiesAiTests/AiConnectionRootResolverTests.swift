@testable import VoyagerEntitiesAi
import XCTest

final class AiConnectionRootResolverTests: XCTestCase {
    func testResolvesFromEnvironmentVariable() {
        let env = ["VOYAGER_PROJECT_ROOT": "/custom/root"]
        let result = AiConnectionRootResolver.resolveBaseRoot(environment: env)
        XCTAssertEqual(result.path, "/custom/root")
    }

    func testEmptyEnvVarIgnored() {
        let env = ["VOYAGER_PROJECT_ROOT": ""]
        let result = AiConnectionRootResolver.resolveBaseRoot(
            environment: env,
            bundle: Bundle(for: type(of: self)),
        )
        XCTAssertNotEqual(result.path, "/custom/root", "Empty env should be ignored")
    }

    func testResolvesToValidURLWhenNoEnvSet() {
        let result = AiConnectionRootResolver.resolveBaseRoot(
            environment: [:],
            bundle: Bundle(for: type(of: self)),
        )
        XCTAssertTrue(result.isFileURL, "Should resolve to a file URL")
    }
}

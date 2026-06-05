import XCTest

final class AuthFixtureTests: XCTestCase {
    func testAuthFileIsWrittenUnderTempHome() throws {
        let fixture = try AuthTestFixture()
        try fixture.writeAuthFile(FixtureCredentials.authJSON)

        let data = try fixture.readAuthFile()
        let contents = String(data: data, encoding: .utf8)!
        XCTAssertTrue(
            contents.contains("chatgpt-codex"),
            "Auth file should contain provider name"
        )
        XCTAssertTrue(
            fixture.authFileURL.path.contains(fixture.homeURL.lastPathComponent),
            "Auth file must live under the temporary home, not real ~/.voyager"
        )
    }

    func testAuthFileHasRestrictedPermissions() throws {
        let fixture = try AuthTestFixture()
        try fixture.writeAuthFile(FixtureCredentials.authJSON)

        XCTAssertTrue(
            fixture.authFileHasRestrictedPermissions(),
            "Auth file must be 0o600 (owner read/write only)"
        )
    }

    func testTempHomeDoesNotCollideWithRealHome() throws {
        let fixture = try AuthTestFixture()
        let realHome = NSHomeDirectory()
        XCTAssertFalse(
            fixture.homeURL.path.hasPrefix(realHome),
            "Temp fixture home must not overlap with real HOME"
        )
    }
}

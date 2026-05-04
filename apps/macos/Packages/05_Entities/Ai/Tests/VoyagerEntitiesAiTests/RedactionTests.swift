import XCTest

final class RedactionTests: XCTestCase {
    func testRawSecretsAreDetectedInOutput() {
        let dirty = "refresh=\(FixtureCredentials.refreshToken)"
        XCTAssertTrue(
            dirty.contains(FixtureCredentials.refreshToken),
            "Dirty output must contain the raw fixture token"
        )
    }

    func testNoRawSecretsInCleanOutput() {
        let helper = RedactionTestHelper()
        let clean = "refresh=<redacted> provider=chatgpt-codex"
        helper.assertNoRawSecrets(in: clean)
    }

    func testRedactionFunctionMasksAllSecrets() {
        let helper = RedactionTestHelper()
        helper.assertRedaction { raw in
            var result = raw
            for secret in FixtureCredentials.allSecrets {
                result = result.replacingOccurrences(
                    of: secret,
                    with: RedactionTestHelper.defaultRedacted
                )
            }
            return result
        }
    }

    func testFixtureCredentialsDoNotContainEmptyStrings() {
        for secret in FixtureCredentials.allSecrets {
            XCTAssertFalse(secret.isEmpty, "Fixture secret must not be empty")
        }
    }
}

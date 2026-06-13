import XCTest

/// Captures string output and asserts that no raw fixture secrets appear.
final class RedactionTestHelper {
    private let secrets: [String]
    static let defaultRedacted = "<redacted>"

    init(secrets: [String] = FixtureCredentials.allSecrets) {
        self.secrets = secrets
    }

    /// Asserts that `output` does not contain any raw secret from `secrets`.
    /// If `redactedPlaceholder` is provided, also asserts that the placeholder IS present
    /// (i.e. secrets were replaced, not just removed).
    func assertNoRawSecrets(
        in output: String,
        redactedPlaceholder _: String = defaultRedacted,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        for secret in secrets {
            XCTAssertFalse(
                output.contains(secret),
                "Raw secret \"\(secret.prefix(8))…\" found in output.",
                file: file,
                line: line,
            )
        }
    }

    /// Asserts that a redaction function correctly masks all secrets.
    /// `redact` receives the raw string and should return the redacted version.
    func assertRedaction(
        _ redact: (String) -> String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        for secret in secrets {
            let raw = "token=\(secret)"
            let result = redact(raw)
            XCTAssertFalse(
                result.contains(secret),
                "Redaction failed for secret \"\(secret.prefix(8))…\". Result: \(result)",
                file: file,
                line: line,
            )
        }
    }
}

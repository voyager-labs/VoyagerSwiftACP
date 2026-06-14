@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiProviderLiveSmokeTests: XCTestCase {
    private func makeRuntimeClient() -> AiConnectionRuntimeClient {
        AiConnectionRuntimeClient.live()
    }

    private func liveSecret(
        envVar: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws -> String {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment[envVar]?.isEmpty ?? true,
            "Environment variable \(envVar) not set — skipping live smoke test",
            file: file,
            line: line,
        )
        guard let value = ProcessInfo.processInfo.environment[envVar], !value.isEmpty else {
            XCTFail("Environment variable \(envVar) unexpectedly nil after XCTSkipIf", file: file, line: line)
            fatalError("unreachable after XCTFail")
        }
        return value
    }

    // MARK: - OpenAI

    func testLiveVerify_openAI_validKey() async throws {
        let secret = try liveSecret(envVar: "VOYAGER_LIVE_OPENAI_API_KEY")
        let client = makeRuntimeClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: secret))
        let result = await client.verifyProvider(.openai, credential)
        switch result {
        case .valid:
            break
        case let .invalid(reason):
            XCTFail("OpenAI verification failed with reason: \(reason.rawValue)")
        case .networkError:
            XCTFail("OpenAI verification hit network error — check connectivity")
        case .unsupportedProvider:
            XCTFail("OpenAI should not be unsupported")
        }
    }

    func testLiveVerify_openAI_invalidKey() async {
        let client = makeRuntimeClient()
        let credential = StoredCredentialPayload.apiKey(
            APIKeyCredentialFile(secret: "sk-clearly-invalid-test-key"),
        )
        let result = await client.verifyProvider(.openai, credential)
        switch result {
        case .valid:
            XCTFail("Invalid OpenAI key should not verify as valid")
        case .invalid:
            break // expected
        case .networkError:
            break // acceptable — network may be unavailable in CI
        case .unsupportedProvider:
            XCTFail("OpenAI should not be unsupported")
        }
    }

    // MARK: - Anthropic

    func testLiveVerify_anthropic_validKey() async throws {
        let secret = try liveSecret(envVar: "VOYAGER_LIVE_ANTHROPIC_API_KEY")
        let client = makeRuntimeClient()
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: secret))
        let result = await client.verifyProvider(.anthropic, credential)
        switch result {
        case .valid:
            break
        case let .invalid(reason):
            XCTFail("Anthropic verification failed with reason: \(reason.rawValue)")
        case .networkError:
            XCTFail("Anthropic verification hit network error — check connectivity")
        case .unsupportedProvider:
            XCTFail("Anthropic should not be unsupported")
        }
    }

    func testLiveVerify_anthropic_invalidKey() async {
        let client = makeRuntimeClient()
        let credential = StoredCredentialPayload.apiKey(
            APIKeyCredentialFile(secret: "sk-ant-clearly-invalid-test-key"),
        )
        let result = await client.verifyProvider(.anthropic, credential)
        switch result {
        case .valid:
            XCTFail("Invalid Anthropic key should not verify as valid")
        case .invalid:
            break // expected
        case .networkError:
            break // acceptable — network may be unavailable in CI
        case .unsupportedProvider:
            XCTFail("Anthropic should not be unsupported")
        }
    }

    // MARK: - Codex OAuth (non-interactive fixture not available)

    func testLiveVerify_codexOAuth_skipped() throws {
        try XCTSkipIf(
            true,
            "Codex OAuth requires interactive browser login — " +
                "no non-interactive fixture available for automated smoke testing",
        )
    }
}

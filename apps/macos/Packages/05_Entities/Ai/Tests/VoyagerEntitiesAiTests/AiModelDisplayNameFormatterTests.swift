@testable import VoyagerEntitiesAi
import XCTest

final class AiModelDisplayNameFormatterTests: XCTestCase {
    func testDisplayName_openAIFamilyUsesCanonicalMarketingCasing() {
        XCTAssertEqual(format(.openai, rawModelID: "gpt-5.5"), "GPT-5.5")
        XCTAssertEqual(format(.openai, rawModelID: "gpt-5.4-mini"), "GPT-5.4 Mini")
        XCTAssertEqual(format(.openai, rawModelID: "gpt-5.3-codex-spark"), "GPT-5.3 Codex Spark")
        XCTAssertEqual(format(.openai, rawModelID: "gpt-5-pro"), "GPT-5 Pro")
        XCTAssertEqual(format(.openai, rawModelID: "o4-mini"), "o4-mini")
    }

    func testDisplayName_anthropicFamilyUsesClaudeMarketingNames() {
        XCTAssertEqual(format(.anthropic, rawModelID: "claude-sonnet-4-6"), "Claude Sonnet 4.6")
        XCTAssertEqual(format(.anthropic, rawModelID: "claude-opus-4-7"), "Claude Opus 4.7")
        XCTAssertEqual(format(.anthropic, rawModelID: "claude-haiku-4-5-20251001"), "Claude Haiku 4.5")
        XCTAssertEqual(format(.anthropic, rawModelID: "claude-3-5-sonnet-20240620"), "Claude Sonnet 3.5")
    }

    func testDisplayName_preservesProviderDisplayNameForCustomOrSpecialModels() {
        XCTAssertEqual(
            format(.chatgptCodex, rawModelID: "codex-auto-review", providerDisplayName: "Codex Auto Review"),
            "Codex Auto Review"
        )
        XCTAssertEqual(
            format(.anthropic, rawModelID: "claude-custom", providerDisplayName: "Custom Claude Router"),
            "Custom Claude Router"
        )
        XCTAssertEqual(format(.openai, rawModelID: "custom-openai-model"), "custom-openai-model")
    }

    private func format(
        _ provider: AiProvider,
        rawModelID: String,
        providerDisplayName: String? = nil
    ) -> String {
        AiModelDisplayNameFormatter.displayName(
            provider: provider,
            rawModelID: rawModelID,
            providerDisplayName: providerDisplayName
        )
    }
}

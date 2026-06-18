@testable import VoyagerEntitiesAi
import XCTest

final class CollectionSearchAISelectionPolicyTests: XCTestCase {
    func testSupportsQueryConversionFiltersUnsupportedOpenAIModels() {
        let supported = AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o-mini"),
            provider: .openai,
            rawModelID: "gpt-4o-mini",
            displayName: "GPT-4o mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unknown(reason: .init(message: "")),
            unavailableReason: nil,
        )
        let unsupported = AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o-mini-search"),
            provider: .openai,
            rawModelID: "gpt-4o-mini-search",
            displayName: "GPT-4o mini Search",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unknown(reason: .init(message: "")),
            unavailableReason: nil,
        )

        XCTAssertTrue(CollectionSearchAISelectionPolicy.supportsQueryConversion(supported))
        XCTAssertFalse(CollectionSearchAISelectionPolicy.supportsQueryConversion(unsupported))
    }

    func testNormalizeSelectedThinkingFallsBackWhenUnsupported() {
        let model = AiProviderModel(
            id: .init(provider: .openai, rawValue: "gpt-4o-mini"),
            provider: .openai,
            rawModelID: "gpt-4o-mini",
            displayName: "GPT-4o mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unsupported(reason: .init(message: "no thinking")),
            unavailableReason: nil,
        )

        XCTAssertNil(CollectionSearchAISelectionPolicy.normalizeSelectedThinking(.none, for: model))
    }

    func testThinkingOptionsIncludeDefaultWhenSupported() {
        let model = AiProviderModel(
            id: .init(provider: .anthropic, rawValue: "claude-3-5-sonnet"),
            provider: .anthropic,
            rawModelID: "claude-3-5-sonnet",
            displayName: "Claude 3.5 Sonnet",
            providerDisplayName: "Anthropic",
            thinkingCapability: .effort(values: [.minimal, .low], defaultValue: .low),
            supportsThinkingNone: true,
            unavailableReason: nil,
        )

        let options = CollectionSearchAISelectionPolicy.thinkingOptions(for: model)
        XCTAssertEqual(options.first?.title, "Provider default")
        XCTAssertTrue(options.contains(where: { $0.selection == .none }))
        XCTAssertTrue(options.contains(where: { $0.selection == .effort(.low) }))
    }
}

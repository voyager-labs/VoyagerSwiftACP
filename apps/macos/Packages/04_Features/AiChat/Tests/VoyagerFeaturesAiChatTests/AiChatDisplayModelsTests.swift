import Foundation
@testable import VoyagerFeaturesAiChat
import XCTest

final class AiChatDisplayModelsTests: XCTestCase {
    func testMockAssistantBodyLinesReturnsShortEnglishLinesForDeterministicPayload() {
        let content = """
        Voyager AI
        Context checked.
        Plan ready.
        Provider later.
        ✓ Context
        ✓ Queued
        ★ Mock ready
        """

        XCTAssertEqual(aiChatMockAssistantBodyLines(from: content), [
            "Context checked.",
            "Plan ready.",
            "Provider later."
        ])
    }

    func testMockAssistantBodyLinesReturnsNilForNonMockContentContainingReservedStrings() {
        let content = """
        Analysis note
        Voyager AI
        This text keeps ✓ Queued as content.
        It should remain regular body text.
        """

        XCTAssertNil(aiChatMockAssistantBodyLines(from: content))
    }
}

@testable import VoyagerFeaturesAiChat
import XCTest

final class AiChatAssistantMarkdownBlockTests: XCTestCase {
    func testParseAssistantMarkdownBlocksForHeadingsListsAndCodeFence() {
        let blocks = AssistantMarkdownBlock.parse("""
        ### Summary

        - first bullet
        * second bullet
        1. numbered item

        Paragraph with **bold** text.

        ```swift
        let value = 1
        ```
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 3, text: "Summary"),
            .bullet("first bullet"),
            .bullet("second bullet"),
            .numbered(number: 1, text: "numbered item"),
            .paragraph("Paragraph with **bold** text."),
            .code("let value = 1"),
        ])
    }

    func testParseFallsBackToParagraphForUnclosedCodeFence() {
        let blocks = AssistantMarkdownBlock.parse("""
        ```swift
        let value = 1
        """)

        XCTAssertEqual(blocks, [
            .paragraph("```\nlet value = 1"),
        ])
    }
}

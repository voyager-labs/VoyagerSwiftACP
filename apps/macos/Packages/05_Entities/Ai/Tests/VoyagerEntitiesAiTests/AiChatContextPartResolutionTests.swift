import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatContextPartResolutionTests: XCTestCase {
    func testResolvedText_mapsToInlineText() {
        let result = AiChatAttachmentResolutionResult.resolvedText(
            text: "Resolved note body",
            metadata: ["encoding": "utf-8"],
        )

        XCTAssertEqual(
            result.contextPartResolution,
            .inlineText(text: "Resolved note body", metadata: ["encoding": "utf-8"]),
        )
    }

    func testResolvedPartial_mapsToPartialText() {
        let result = AiChatAttachmentResolutionResult.resolvedPartial(
            text: "Partial body",
            truncated: true,
            metadata: ["encoding": "utf-8"],
        )

        XCTAssertEqual(
            result.contextPartResolution,
            .partialText(text: "Partial body", truncated: true, metadata: ["encoding": "utf-8"]),
        )
    }

    func testResolvedReference_mapsToReferenceOnlyWithoutCollectionPaths() {
        let result = AiChatAttachmentResolutionResult.resolvedReference(
            metadata: ["resolution": "reference_only"],
        )

        XCTAssertEqual(
            result.contextPartResolution,
            .referenceOnly(metadata: ["resolution": "reference_only"]),
        )
    }

    func testFailure_mapsToFailurePreservingReasonAndMetadata() {
        let result = AiChatAttachmentResolutionResult.failure(
            reason: .permissionDenied,
            metadata: ["path": "/tmp/Secrets.txt"],
        )

        XCTAssertEqual(
            result.contextPartResolution,
            .failure(reason: .permissionDenied, metadata: ["path": "/tmp/Secrets.txt"]),
        )
    }
}

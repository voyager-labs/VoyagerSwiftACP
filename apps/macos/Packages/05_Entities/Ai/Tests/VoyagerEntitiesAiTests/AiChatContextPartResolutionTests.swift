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

    func testResolvedReference_mapsCollectionPathsToCollectionPathList() {
        let result = AiChatAttachmentResolutionResult.resolvedReference(
            metadata: [
                "collectionItemCount": "2",
                "collectionItemPaths": "/tmp/project/README.md\n/tmp/project/design.pdf\n",
                "collectionItemsIncluded": "2",
            ],
        )

        XCTAssertEqual(
            result.contextPartResolution,
            .collectionPathList(
                paths: ["/tmp/project/README.md", "/tmp/project/design.pdf"],
                metadata: [
                    "collectionItemCount": "2",
                    "collectionItemsIncluded": "2",
                ],
            ),
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

    func testContextPartResolution_roundTripsProviderNativeFileKind() throws {
        let resolution = AiChatContextPartResolution.providerNativeFile(
            kind: .openAIDocument,
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            metadata: ["source": "upload"],
        )

        let encoded = try JSONEncoder().encode(resolution)
        let decoded = try JSONDecoder().decode(AiChatContextPartResolution.self, from: encoded)

        XCTAssertEqual(decoded, resolution)
    }
}

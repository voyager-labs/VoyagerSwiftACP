import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderFileCapabilityTests: XCTestCase {
    func testOpenAIPDFAllowedOnResponsesButBlockedByRouteAndModel() {
        let file = FileMeta(
            fileExtension: "pdf",
            mimeType: "application/pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 512_000,
        )
        let allowed = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            file: file,
        )
        XCTAssertEqual(
            allowed.disposition,
            .providerNativeUpload(kind: .pdf, mimeType: "application/pdf"),
        )

        let blockedRoute = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIChatCompletions,
            file: file,
        )
        XCTAssertEqual(blockedRoute.disposition, .fallback(.routeNotAllowlisted))

        let blockedModel = lookup(
            provider: .openai,
            rawModelID: "gpt-3.5-turbo",
            requestFamily: .openAIResponses,
            file: file,
        )
        XCTAssertEqual(blockedModel.disposition, .fallback(.modelNotAllowlisted))
    }

    func testAnthropicDocxDoesNotBecomeNative() {
        let decision = lookup(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestFamily: .anthropicMessages,
            file: FileMeta(
                fileExtension: "docx",
                mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                contentTypeIdentifier: "org.openxmlformats.wordprocessingml.document",
                sizeBytes: 128_000,
            ),
        )

        XCTAssertEqual(decision.disposition, .fallback(.unknownExtension))
        XCTAssertFalse(decision.producesProviderNativeUpload)
    }

    func testMIMEMismatchBlocksNativeUpload() {
        let mismatchedPDF = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            file: FileMeta(
                fileExtension: "pdf",
                mimeType: "text/plain",
                contentTypeIdentifier: "public.plain-text",
                sizeBytes: 1024,
            ),
        )
        XCTAssertEqual(mismatchedPDF.disposition, .fallback(.mimeTypeMismatch))

        let octetStreamText = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            file: FileMeta(
                fileExtension: "txt",
                mimeType: "application/octet-stream",
                contentTypeIdentifier: nil,
                sizeBytes: 1024,
            ),
        )
        XCTAssertEqual(octetStreamText.disposition, .fallback(.unknownMIMEType))
    }

    func testUnknownExtensionNeverBecomesNative() {
        let decision = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            file: FileMeta(
                fileExtension: "foo",
                mimeType: "text/plain",
                contentTypeIdentifier: "public.plain-text",
                sizeBytes: 2048,
            ),
        )

        XCTAssertEqual(decision.disposition, .fallback(.unknownExtension))
        XCTAssertFalse(decision.producesProviderNativeUpload)
    }

    func testSafeLimitFallsBackToTooLargeForNative() {
        let decision = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            file: FileMeta(
                fileExtension: "png",
                mimeType: "image/png",
                contentTypeIdentifier: "public.png",
                sizeBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes + 1,
            ),
        )

        XCTAssertEqual(decision.disposition, .fallback(.tooLargeForNative))
        XCTAssertTrue(decision.tooLargeForNative)
    }

    func testCodexUsesPathScopeNotProviderNativeUpload() {
        let decision = lookup(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            requestFamily: .codexCLI,
            file: FileMeta(
                fileExtension: "pdf",
                mimeType: "application/octet-stream",
                contentTypeIdentifier: nil,
                sizeBytes: 50 * 1024 * 1024,
            ),
        )

        XCTAssertEqual(decision.disposition, .codexPathScope)
        XCTAssertFalse(decision.producesProviderNativeUpload)
    }

    func testMimeDetectionPolicyMatchesPlannedOrder() {
        XCTAssertEqual(
            AiChatProviderFileCapability.mimeDetectionPolicy.orderedSources,
            [
                .urlResourceValuesContentType,
                .filenameExtensionUTType,
                .unknown,
            ],
        )
    }

    private struct FileMeta {
        let fileExtension: String?
        let mimeType: String
        let contentTypeIdentifier: String?
        let sizeBytes: Int64
    }

    private func lookup(
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatProviderRequestFamily,
        file: FileMeta,
    ) -> AiChatProviderFileCapabilityDecision {
        AiChatProviderFileCapability.lookup(
            AiChatProviderFileCapabilityLookup(
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                fileExtension: file.fileExtension,
                detectedMIMEType: file.mimeType,
                sizeBytes: file.sizeBytes,
                detectedContentTypeIdentifier: file.contentTypeIdentifier,
            ),
        )
    }
}

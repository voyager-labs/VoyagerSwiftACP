import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderFileCapabilityTests: XCTestCase {
    func testOpenAIPDFAllowedOnResponsesButBlockedByRouteAndModel() {
        let allowed = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            fileExtension: "pdf",
            mimeType: "application/pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 512_000,
        )
        XCTAssertEqual(
            allowed.disposition,
            .providerNativeUpload(kind: .pdf, mimeType: "application/pdf"),
        )

        let blockedRoute = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIChatCompletions,
            fileExtension: "pdf",
            mimeType: "application/pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 512_000,
        )
        XCTAssertEqual(blockedRoute.disposition, .fallback(.routeNotAllowlisted))

        let blockedModel = lookup(
            provider: .openai,
            rawModelID: "gpt-3.5-turbo",
            requestFamily: .openAIResponses,
            fileExtension: "pdf",
            mimeType: "application/pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            sizeBytes: 512_000,
        )
        XCTAssertEqual(blockedModel.disposition, .fallback(.modelNotAllowlisted))
    }

    func testAnthropicDocxDoesNotBecomeNative() {
        let decision = lookup(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestFamily: .anthropicMessages,
            fileExtension: "docx",
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            contentTypeIdentifier: "org.openxmlformats.wordprocessingml.document",
            sizeBytes: 128_000,
        )

        XCTAssertEqual(decision.disposition, .fallback(.unknownExtension))
        XCTAssertFalse(decision.producesProviderNativeUpload)
    }

    func testMIMEMismatchBlocksNativeUpload() {
        let mismatchedPDF = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            fileExtension: "pdf",
            mimeType: "text/plain",
            contentTypeIdentifier: "public.plain-text",
            sizeBytes: 1_024,
        )
        XCTAssertEqual(mismatchedPDF.disposition, .fallback(.mimeTypeMismatch))

        let octetStreamText = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            fileExtension: "txt",
            mimeType: "application/octet-stream",
            contentTypeIdentifier: nil,
            sizeBytes: 1_024,
        )
        XCTAssertEqual(octetStreamText.disposition, .fallback(.unknownMIMEType))
    }

    func testUnknownExtensionNeverBecomesNative() {
        let decision = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            fileExtension: "foo",
            mimeType: "text/plain",
            contentTypeIdentifier: "public.plain-text",
            sizeBytes: 2_048,
        )

        XCTAssertEqual(decision.disposition, .fallback(.unknownExtension))
        XCTAssertFalse(decision.producesProviderNativeUpload)
    }

    func testSafeLimitFallsBackToTooLargeForNative() {
        let decision = lookup(
            provider: .openai,
            rawModelID: "gpt-5",
            requestFamily: .openAIResponses,
            fileExtension: "png",
            mimeType: "image/png",
            contentTypeIdentifier: "public.png",
            sizeBytes: AiChatProviderFileCapability.nativeUploadSafeLimitBytes + 1,
        )

        XCTAssertEqual(decision.disposition, .fallback(.tooLargeForNative))
        XCTAssertTrue(decision.tooLargeForNative)
    }

    func testCodexUsesPathScopeNotProviderNativeUpload() {
        let decision = lookup(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            requestFamily: .codexCLI,
            fileExtension: "pdf",
            mimeType: "application/octet-stream",
            contentTypeIdentifier: nil,
            sizeBytes: 50 * 1024 * 1024,
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

    private func lookup(
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatProviderRequestFamily,
        fileExtension: String?,
        mimeType: String,
        contentTypeIdentifier: String?,
        sizeBytes: Int64,
    ) -> AiChatProviderFileCapabilityDecision {
        AiChatProviderFileCapability.lookup(
            AiChatProviderFileCapabilityLookup(
                provider: provider,
                rawModelID: rawModelID,
                requestFamily: requestFamily,
                fileExtension: fileExtension,
                detectedMIMEType: mimeType,
                detectedContentTypeIdentifier: contentTypeIdentifier,
                sizeBytes: sizeBytes,
            ),
        )
    }
}

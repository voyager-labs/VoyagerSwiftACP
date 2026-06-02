@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class CBW003ProviderRequestPayloadLoweringTests: XCTestCase {
    override func tearDown() {
        ProviderExecutionURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - CBW-003-build_contextual_request_payload

    /// CBW-003-build_contextual_request_payload: OpenAI request는 streaming execution timeout을 사용한다.
    /// OpenAI HTTP request 생성 시 장기 streaming에 맞는 timeout 계약을 추적합니다.
    /// - 검증 내용: request timeout이 공용 streamingExecutionRequestTimeout과 일치하는지 확인합니다.
    /// - 사전 조건: OpenAI payload와 API key credential을 사용합니다.
    /// - 기대 결과: timeout이 30초보다 크고 streaming timeout 상수와 같습니다.
    func testMakeOpenAIRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: makePayload(provider: .openai, rawModelID: "gpt-4.1-mini"),
            credential: .apiKey("openai-key"),
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

    /// CBW-003-build_contextual_request_payload: Anthropic request는 streaming execution timeout을 사용한다.
    /// Anthropic HTTP request 생성 시 streaming timeout 계약을 추적합니다.
    /// - 검증 내용: request timeout이 공용 streamingExecutionRequestTimeout과 일치하는지 확인합니다.
    /// - 사전 조건: Anthropic payload와 API key credential을 사용합니다.
    /// - 기대 결과: timeout이 30초보다 크고 streaming timeout 상수와 같습니다.
    func testMakeAnthropicRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: makePayload(provider: .anthropic, rawModelID: "claude-sonnet-4-20250514"),
            credential: .apiKey("anthropic-key"),
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

    /// CBW-003-build_contextual_request_payload: Anthropic은 허용된 문서와 이미지를 native block으로 전송한다.
    /// provider-native attachment가 prompt text가 아니라 Anthropic content block으로 내려가는지 추적합니다.
    /// - 검증 내용: PDF document와 image block의 media type/source 구성을 확인합니다.
    /// - 사전 조건: native upload가 허용된 Anthropic payload fixture를 사용합니다.
    /// - 기대 결과: native block이 포함되고 fallback prompt에는 base64 payload가 노출되지 않습니다.
    func testMakeAnthropicRequest_usesNativeDocumentAndImageBlocksWhenAllowed() throws {
        try assertAnthropicNativeDocumentAndImageBlocksWhenAllowed()
    }

    /// CBW-003-build_contextual_request_payload: Anthropic current context resolved parts는 attachment transmission 밖에
    /// 포함된다.
    /// 현재 context part와 추가 attachment 전송 섹션이 분리되는지 추적합니다.
    /// - 검증 내용: current_context resolved part와 attachment_transmission 내용을 구분해 확인합니다.
    /// - 사전 조건: resolved current context part가 있는 Anthropic payload를 사용합니다.
    /// - 기대 결과: current context 내용은 포함되고 attachment 전송 상태와 섞이지 않습니다.
    func testMakeAnthropicRequest_includesCurrentContextResolvedPartsOutsideAttachmentTransmission() throws {
        try assertAnthropicCurrentContextResolvedPartsOutsideAttachmentTransmission()
    }

    /// CBW-003-build_contextual_request_payload: OpenAI prompt는 folder metadata를 current context와 attachment에 반영한다.
    /// 폴더/컬렉션 reference metadata가 payload prompt로 안전하게 lower되는지 추적합니다.
    /// - 검증 내용: resolved folder metadata와 collection path list가 prompt에 포함되는지 확인합니다.
    /// - 사전 조건: current context와 added attachment에 folder metadata fixture를 사용합니다.
    /// - 기대 결과: metadata 요약은 포함되고 절대 경로 민감 정보는 확장되지 않습니다.
    func testMakeOpenAIRequest_includesResolvedFolderMetadataForCurrentContextAndAttachments() throws {
        try assertOpenAIResolvedFolderMetadataForCurrentContextAndAttachments()
    }

    /// CBW-003-build_contextual_request_payload: Anthropic system prompt는 base64 payload metadata를 숨긴다.
    /// native upload metadata가 system prompt에 민감 정보로 누수되지 않는지 추적합니다.
    /// - 검증 내용: base64, byte count, source path가 prompt에 포함되지 않는지 확인합니다.
    /// - 사전 조건: base64 native attachment가 있는 Anthropic payload를 사용합니다.
    /// - 기대 결과: prompt에는 안전한 표시 정보만 남고 binary payload metadata는 빠집니다.
    func testMakeAnthropicRequest_omitsBase64PayloadMetadataFromSystemPrompt() throws {
        try assertAnthropicOmitsBase64PayloadMetadataFromSystemPrompt()
    }

    /// CBW-003-build_contextual_request_payload: prompt metadata는 허용된 요약 key만 출력한다.
    /// 신규 metadata key가 추가되어도 file path, base64 payload, 내부 식별자가 provider prompt에 누수되지 않는지 추적합니다.
    /// - 검증 내용: allow-list key는 남고 미허용 key 이름과 값은 제외되는지 확인합니다.
    /// - 사전 조건: 안전 key와 민감 key가 섞인 current context 및 attachment metadata를 사용합니다.
    /// - 기대 결과: prompt에는 encoding/resolution만 남고 raw payload/path/internal id는 포함되지 않습니다.
    func testMakeAnthropicRequest_omitsUnapprovedPromptMetadataKeys() throws {
        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: makePromptMetadataAllowListPayload(),
            credential: .apiKey("anthropic-key"),
        )
        let decoded = try decodeAnthropicRequestBody(request)
        let system = try XCTUnwrap(decoded.system)

        XCTAssertTrue(system.contains("encoding: utf-8"), system)
        XCTAssertTrue(system.contains("resolution: reference_only"), system)
        XCTAssertFalse(system.contains("originalFilePath:"), system)
        XCTAssertFalse(system.contains("rawBase64Payload:"), system)
        XCTAssertFalse(system.contains("attachmentMetadata:"), system)
        XCTAssertFalse(system.contains("providerInternalAttachmentID:"), system)
        XCTAssertFalse(system.contains("/Users/me/secret/Secret.swift"), system)
        XCTAssertFalse(system.contains("CURRENT_CONTEXT_RAW_BYTES"), system)
        XCTAssertFalse(system.contains("INTERNAL_ATTACHMENT_METADATA"), system)
        XCTAssertFalse(system.contains("ATTACHMENT_INTERNAL_ID"), system)
    }

    private func makePromptMetadataAllowListPayload() throws -> AiChatProviderRequestPayload {
        try makePayload(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "Locked metadata context",
                    items: [makePromptMetadataAllowListItem()],
                ),
                addedAttachments: [makePromptMetadataAllowListAttachment()],
            ),
        )
    }

    private func makePromptMetadataAllowListItem() -> AiChatContextItem {
        AiChatContextItem(
            kind: .file,
            identifier: "secret-file",
            title: "Secret.swift",
            metadata: [
                "encoding": "utf-8",
                "originalFilePath": "/Users/me/secret/Secret.swift",
                "rawBase64Payload": "CURRENT_CONTEXT_RAW_BYTES",
            ],
        )
    }

    private func makePromptMetadataAllowListAttachment() -> AiChatAttachmentSnapshot {
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "secret-attachment"),
            source: .file,
            displayTitle: "SecretAttachment.txt",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "SecretAttachment.txt"),
            metadata: ["attachmentMetadata": "INTERNAL_ATTACHMENT_METADATA"],
            resolutionResult: .resolvedReference(metadata: [
                "providerInternalAttachmentID": "ATTACHMENT_INTERNAL_ID",
                "resolution": "reference_only",
            ]),
        )
    }

    /// CBW-003-build_contextual_request_payload: Anthropic native upload 불가 항목은 prompt-only fallback으로 내려간다.
    /// provider-native 전송이 불가능한 attachment가 텍스트 fallback으로 안전하게 표현되는지 추적합니다.
    /// - 검증 내용: unsupported/too-large 항목의 fallback prompt와 redaction을 확인합니다.
    /// - 사전 조건: native upload disallowed 또는 size 초과 attachment fixture를 사용합니다.
    /// - 기대 결과: native block 없이 prompt-only 설명이 포함되고 절대 경로는 노출되지 않습니다.
    func testMakeAnthropicRequest_fallsBackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
        try assertAnthropicFallbackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge()
    }

    /// CBW-003-build_contextual_request_payload: OpenAI thinking none은 reasoning effort none으로 인코딩된다.
    /// 지원 모델에서 none 선택이 OpenAI reasoning payload에 명시되는지 추적합니다.
    /// - 검증 내용: decoded reasoning effort와 budget token 값을 확인합니다.
    /// - 사전 조건: OpenAI gpt-5 payload에 thinking none을 설정합니다.
    /// - 기대 결과: reasoning.effort는 none이고 budgetTokens는 비어 있습니다.
    func testMakeOpenAIRequest_encodesReasoningWhenThinkingNoneIsSupported() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-5",
            thinking: AiChatProviderThinkingPayload.none,
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(PayloadCapturedOpenAIRequestBody.self, from: body)

        XCTAssertEqual(decoded.reasoning?.effort, "none")
        XCTAssertNil(decoded.reasoning?.budgetTokens)
    }

    /// CBW-003-build_contextual_request_payload: attachment가 없어도 OpenAI prompt는 locked current context를 사용한다.
    /// live draft 대신 locked context snapshot만 prompt에 들어가는지 추적합니다.
    /// - 검증 내용: current_context summary, selection item, empty attachment 섹션을 확인합니다.
    /// - 사전 조건: current context만 있고 attachment가 없는 locked snapshot을 사용합니다.
    /// - 기대 결과: locked context가 포함되고 live draft 문구는 누락됩니다.
    func testMakeOpenAIRequest_usesLockedCurrentContextWhenNoAttachmentsExist() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "Locked editor selection",
                    items: [
                        AiChatContextItem(
                            kind: .selection,
                            identifier: "selection-1",
                            title: "Lines 10-20",
                            metadata: ["path": "/tmp/Selection.swift"],
                        ),
                    ],
                ),
                addedAttachments: [],
            ),
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user"])
        XCTAssertEqual(decoded.input.first?.type, "message")
        XCTAssertTrue(prompt.contains("current_context:"))
        XCTAssertTrue(prompt.contains("summary: Locked editor selection"))
        XCTAssertTrue(prompt.contains("[selection] Lines 10-20"))
        XCTAssertTrue(prompt.contains("added_attachments:\n  - none"))
        XCTAssertFalse(prompt.contains("live draft should not leak"))
    }

    /// CBW-003-build_contextual_request_payload: OpenAI history는 assistant output text를 message content로 사용한다.
    /// 대화 이력이 provider input role/content 순서로 보존되는지 추적합니다.
    /// - 검증 내용: user, assistant, user message 순서와 content 값을 확인합니다.
    /// - 사전 조건: 세 개의 conversation message fixture를 사용합니다.
    /// - 기대 결과: decoded input role과 text가 원본 history와 일치합니다.
    func testMakeOpenAIRequest_usesOutputTextForAssistantHistory() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            messages: [
                AiChatProviderMessage(role: .user, content: "First question"),
                AiChatProviderMessage(role: .assistant, content: "First answer"),
                AiChatProviderMessage(role: .user, content: "Follow-up question"),
            ],
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let decoded = try decodeOpenAIRequestBody(request)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user", "assistant", "user"])
        XCTAssertEqual(decoded.input[1].content.text, "First question")
        XCTAssertEqual(decoded.input[2].content.text, "First answer")
        XCTAssertEqual(decoded.input[3].content.text, "Follow-up question")
    }

    /// CBW-003-build_contextual_request_payload: OpenAI prompt는 locked attachment resolution variant만 포함한다.
    /// resolvedText, resolvedReference, failure attachment가 snapshot 기준으로 표현되는지 추적합니다.
    /// - 검증 내용: text body, collection metadata, failure reason 표기를 확인합니다.
    /// - 사전 조건: 여러 resolution variant가 섞인 locked attachment fixture를 사용합니다.
    /// - 기대 결과: locked attachment 내용만 포함되고 live attachment 문구는 누락됩니다.
    func testMakeOpenAIRequest_includesLockedAttachmentResolutionVariantsOnly() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(summary: "Locked request context"),
                addedAttachments: makeLockedAttachmentResolutionFixtures(),
            ),
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("Notes.txt [resolvedText]"))
        XCTAssertTrue(prompt.contains("Resolved note body"))
        XCTAssertTrue(prompt.contains("Workspace [resolvedReference]"))
        XCTAssertTrue(prompt.contains("reference included; content not expanded."))
        XCTAssertTrue(prompt.contains("Workspace.voycoll [resolvedReference]"))
        XCTAssertTrue(prompt.contains("collection_items:"))
        XCTAssertTrue(prompt.contains("- /tmp/project/README.md"))
        XCTAssertTrue(prompt.contains("- /tmp/project/design.pdf"))
        XCTAssertTrue(prompt.contains("collection_items_included: 2"))
        XCTAssertTrue(prompt.contains("collection_item_count: 2"))
        XCTAssertTrue(prompt.contains("collection references included; content not expanded."))
        XCTAssertTrue(prompt.contains("Broken.txt [readFailed]"))
        XCTAssertTrue(prompt.contains("not included: readFailed"))
        XCTAssertFalse(prompt.contains("live attachment should not leak"))
    }

    /// CBW-003-build_contextual_request_payload: OpenAI prompt는 added attachment 절대 경로를 redaction한다.
    /// 로컬 파일 경로가 provider prompt에 그대로 노출되지 않는지 추적합니다.
    /// - 검증 내용: display filename은 남고 /Users 경로 prefix가 빠지는지 확인합니다.
    /// - 사전 조건: 절대 경로를 가진 resolvedText attachment fixture를 사용합니다.
    /// - 기대 결과: prompt에는 파일명만 포함되고 사용자 홈 경로는 포함되지 않습니다.
    func testMakeOpenAIRequest_redactsAddedAttachmentAbsoluteFilePathInPrompt() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "secret-notes"),
                        source: .file,
                        displayTitle: "SecretNotes.txt",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(
                            filePath: "/Users/me/secret/docs/SecretNotes.txt",
                        ),
                        resolutionResult: .resolvedText(text: "safe body", metadata: ["encoding": "utf-8"]),
                    ),
                ],
                parts: [],
            ),
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("file_path: SecretNotes.txt"), prompt)
        XCTAssertFalse(prompt.contains("/Users/me/secret"), prompt)
    }

    /// CBW-003-build_contextual_request_payload: OpenAI는 허용된 이미지와 파일을 native content block으로 전송한다.
    /// OpenAI native upload lowering이 image/file block을 올바르게 구성하는지 추적합니다.
    /// - 검증 내용: decoded input content에서 image와 file block metadata를 확인합니다.
    /// - 사전 조건: native image와 document가 포함된 OpenAI payload fixture를 사용합니다.
    /// - 기대 결과: provider-native block이 포함되고 prompt-only fallback으로 중복되지 않습니다.
    func testMakeOpenAIRequest_usesNativeImageAndFileBlocksWhenAllowed() throws {
        try assertOpenAINativeImageAndFileBlocksWhenAllowed()
    }

    /// CBW-003-build_contextual_request_payload: OpenAI native upload 불가 항목은 prompt-only fallback으로 내려간다.
    /// OpenAI native 전송 대상에서 제외된 attachment가 안전한 prompt 설명으로 대체되는지 추적합니다.
    /// - 검증 내용: fallback prompt, unsupported/too-large 상태, 경로 redaction을 확인합니다.
    /// - 사전 조건: native upload가 불가하거나 크기 제한을 넘는 OpenAI payload fixture를 사용합니다.
    /// - 기대 결과: native block 없이 fallback 설명만 포함되고 절대 경로는 노출되지 않습니다.
    func testMakeOpenAIRequest_fallsBackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
        try assertOpenAIFallbackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge()
    }

    /// CBW-003-build_contextual_request_payload: 빈 locked context는 불필요한 context prompt를 만들지 않는다.
    /// context가 비어 있을 때 provider prompt가 최소 사용자 메시지만 유지하는지 추적합니다.
    /// - 검증 내용: developer/context prompt 부재와 user message content를 확인합니다.
    /// - 사전 조건: empty locked context와 attachment 없는 payload를 사용합니다.
    /// - 기대 결과: context prompt 없이 사용자 메시지만 OpenAI input에 포함됩니다.
    func testMakeOpenAIRequest_allowsEmptyLockedContextWithoutContextPrompt() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(currentContext: .init(), addedAttachments: []),
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key"),
        )
        let decoded = try decodeOpenAIRequestBody(request)

        XCTAssertEqual(decoded.input.map(\.role), ["user"])
        XCTAssertEqual(decoded.input.first?.content.text, "Hello")
    }

    /// CBW-003-build_contextual_request_payload: collection reference metadata는 path list로 정규화된다.
    /// collectionItems metadata가 provider prompt용 path list로 변환되는지 추적합니다.
    /// - 검증 내용: collection path list와 truncation/count metadata를 확인합니다.
    /// - 사전 조건: collection item metadata를 가진 resolvedReference fixture를 사용합니다.
    /// - 기대 결과: collection paths가 항목별 list로 보존됩니다.
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

    /// CBW-003-build_contextual_request_payload: provider native file kind는 context part resolution에서 round-trip된다.
    /// native file kind enum이 encoding/decoding 과정에서 손실되지 않는지 추적합니다.
    /// - 검증 내용: context part resolution JSON round-trip 결과의 native file kind를 확인합니다.
    /// - 사전 조건: provider-native file kind를 가진 resolution fixture를 사용합니다.
    /// - 기대 결과: decoded value가 원본 provider native file kind와 일치합니다.
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

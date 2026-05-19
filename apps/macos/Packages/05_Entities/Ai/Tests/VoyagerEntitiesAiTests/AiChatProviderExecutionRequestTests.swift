import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderExecutionRequestTests: XCTestCase {
    func testMakeOpenAIRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: makePayload(provider: .openai, rawModelID: "gpt-4.1-mini"),
            credential: .apiKey("openai-key"),
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

    func testMakeAnthropicRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: makePayload(provider: .anthropic, rawModelID: "claude-sonnet-4-20250514"),
            credential: .apiKey("anthropic-key"),
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

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
        let decoded = try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)

        XCTAssertEqual(decoded.reasoning?.effort, "none")
        XCTAssertNil(decoded.reasoning?.budgetTokens)
    }

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
        let prompt = try XCTUnwrap(decoded.input.first?.content)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user"])
        XCTAssertTrue(prompt.contains("current_context:"))
        XCTAssertTrue(prompt.contains("summary: Locked editor selection"))
        XCTAssertTrue(prompt.contains("[selection] Lines 10-20"))
        XCTAssertTrue(prompt.contains("added_attachments:\n  - none"))
        XCTAssertFalse(prompt.contains("live draft should not leak"))
    }

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
        let prompt = try XCTUnwrap(decoded.input.first?.content)

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
        XCTAssertEqual(decoded.input.first?.content, "Hello")
    }

    func testCodexArguments_includeReasoningEffortWhenSelected() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        let arguments = AiChatProviderExecutionClient.codexArguments(
            model: "gpt-5-codex",
            outputURL: outputURL,
            prompt: "Explain the change",
            thinking: .effort(.high),
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--json",
            "--model",
            "gpt-5-codex",
            "--output-last-message",
            outputURL.path,
            "-c",
            "model_reasoning_effort=\"high\"",
            "Explain the change",
        ])
    }

    func testCodexArguments_includeReasoningNoneWhenSupported() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        let arguments = AiChatProviderExecutionClient.codexArguments(
            model: "gpt-5-codex",
            outputURL: outputURL,
            prompt: "Explain the change",
            thinking: AiChatProviderThinkingPayload.none,
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--json",
            "--model",
            "gpt-5-codex",
            "--output-last-message",
            outputURL.path,
            "-c",
            "model_reasoning_effort=\"none\"",
            "Explain the change",
        ])
    }

    func testCodexArguments_omitReasoningEffortWhenUnsupported() {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        for thinking in [nil, .disabled, .tokenBudget(1024)] as [AiChatProviderThinkingPayload?] {
            let arguments = AiChatProviderExecutionClient.codexArguments(
                model: "gpt-5-codex",
                outputURL: outputURL,
                prompt: "Explain the change",
                thinking: thinking,
            )

            XCTAssertFalse(arguments.contains { $0.contains("model_reasoning_effort") })
        }
    }

    func testCodexPipeDataAccumulator_collectsConcurrentStderrChunks() {
        let accumulator = CodexPipeDataAccumulator()

        accumulator.append(Data("first stderr chunk\n".utf8))
        accumulator.append(Data("second stderr chunk".utf8))

        XCTAssertEqual(accumulator.stringValue(), "first stderr chunk\nsecond stderr chunk")
    }

    private func makeLockedAttachmentResolutionFixtures() -> [AiChatAttachmentSnapshot] {
        [
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "text"),
                source: .file,
                displayTitle: "Notes.txt",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Notes.txt"),
                resolutionResult: .resolvedText(
                    text: "Resolved note body",
                    metadata: ["encoding": "utf-8"],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "reference"),
                source: .folder,
                displayTitle: "Workspace",
                kind: .folder,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Workspace"),
                resolutionResult: .resolvedReference(
                    metadata: ["resolution": "reference_only"],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "collection"),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                kind: .attachment,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Workspace.voycoll"),
                resolutionResult: .resolvedReference(
                    metadata: [
                        "collectionItemCount": "2",
                        "collectionItemPaths": "/tmp/project/README.md\n/tmp/project/design.pdf",
                        "collectionItemsIncluded": "2",
                        "collectionItemsTruncated": "false",
                        "collectionSnapshotStatus": "usable",
                    ],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "failure"),
                source: .file,
                displayTitle: "Broken.txt",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Broken.txt"),
                resolutionResult: .failure(
                    reason: .readFailed,
                    metadata: ["path": "/tmp/Broken.txt"],
                ),
            ),
        ]
    }

    private func makePayload(
        provider: AiProvider,
        rawModelID: String,
        thinking: AiChatProviderThinkingPayload? = nil,
        messages: [AiChatProviderMessage] = [
            AiChatProviderMessage(role: .user, content: "Hello"),
        ],
        requestContext: AiChatLockedRequestContextSnapshot = AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(summary: "Request context"),
        ),
    ) throws -> AiChatProviderRequestPayload {
        let requestUUID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runUUID = try XCTUnwrap(UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        let requestID = AiChatRequestID(rawValue: requestUUID)
        let runID = AiChatRunID(rawValue: runUUID)
        return AiChatProviderRequestPayload(
            provider: provider,
            rawModelID: rawModelID,
            messages: messages,
            context: AiChatProviderContextBundle(
                sessionID: nil,
                requestID: requestID,
                runID: runID,
                requestContext: requestContext,
                promptSummary: messages.last?.content,
                submittedAtMs: 1_700_000_000_000,
            ),
            thinking: thinking,
        )
    }

    private func decodeOpenAIRequestBody(_ request: URLRequest) throws -> CapturedOpenAIRequestBody {
        let body = try XCTUnwrap(request.httpBody)
        return try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)
    }
}

private struct CapturedOpenAIRequestBody: Decodable {
    let input: [CapturedOpenAIInputItem]
    let reasoning: CapturedOpenAIReasoning?
}

private struct CapturedOpenAIInputItem: Decodable {
    let role: String
    let content: String
}

private struct CapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

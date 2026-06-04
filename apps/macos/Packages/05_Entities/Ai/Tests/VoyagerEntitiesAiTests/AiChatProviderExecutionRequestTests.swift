import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderExecutionRequestTests: XCTestCase {
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
            "--skip-git-repo-check",
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
            "--skip-git-repo-check",
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

    private func decodeAnthropicRequestBody(_ request: URLRequest) throws -> CapturedAnthropicRequestBody {
        let body = try XCTUnwrap(request.httpBody)
        return try JSONDecoder().decode(CapturedAnthropicRequestBody.self, from: body)
    }
}

private struct CapturedOpenAIRequestBody: Decodable {
    let input: [CapturedOpenAIInputItem]
    let reasoning: CapturedOpenAIReasoning?
}

private struct CapturedOpenAIInputItem: Decodable {
    let type: String?
    let role: String
    let content: CapturedOpenAIContent
}

private enum CapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([CapturedOpenAIContentItem])

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [CapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .parts(container.decode([CapturedOpenAIContentItem].self))
    }
}

private struct CapturedOpenAIContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let detail: String?
    let imageURL: String?
    let fileData: String?
    let filename: String?

    init(
        type: String,
        text: String? = nil,
        detail: String? = nil,
        imageURL: String? = nil,
        fileData: String? = nil,
        filename: String? = nil,
    ) {
        self.type = type
        self.text = text
        self.detail = detail
        self.imageURL = imageURL
        self.fileData = fileData
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case detail
        case imageURL = "image_url"
        case fileData = "file_data"
        case filename
    }
}

private struct CapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

private struct CapturedAnthropicRequestBody: Decodable {
    let messages: [CapturedAnthropicMessage]
    let system: String?
}

private struct CapturedAnthropicMessage: Decodable {
    let role: String
    let content: [CapturedAnthropicContentItem]
}

private struct CapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: CapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    static func image(mediaType: String, data: String) -> Self {
        .init(
            type: "image",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: nil,
        )
    }

    static func document(mediaType: String, data: String, title: String) -> Self {
        .init(
            type: "document",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: title,
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

private struct CapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

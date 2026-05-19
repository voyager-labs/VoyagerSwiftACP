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
            "Explain the change"
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
            "Explain the change"
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

    private func makePayload(
        provider: AiProvider,
        rawModelID: String,
        thinking: AiChatProviderThinkingPayload? = nil,
    ) throws -> AiChatProviderRequestPayload {
        let requestUUID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runUUID = try XCTUnwrap(UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        let requestID = AiChatRequestID(rawValue: requestUUID)
        let runID = AiChatRunID(rawValue: runUUID)
        return AiChatProviderRequestPayload(
            provider: provider,
            rawModelID: rawModelID,
            messages: [
                AiChatProviderMessage(role: .user, content: "Hello")
            ],
            context: AiChatProviderContextBundle(
                sessionID: nil,
                requestID: requestID,
                runID: runID,
                currentContext: AiChatCurrentContextSnapshot(summary: "Request context"),
                promptSummary: "Hello",
                submittedAtMs: 1_700_000_000_000,
            ),
            thinking: thinking,
        )
    }
}

private struct CapturedOpenAIRequestBody: Decodable {
    let reasoning: CapturedOpenAIReasoning?
}

private struct CapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

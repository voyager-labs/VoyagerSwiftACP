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

    func testCodexPipeDataAccumulator_collectsConcurrentStderrChunks() {
        let accumulator = CodexPipeDataAccumulator()

        accumulator.append(Data("first stderr chunk\n".utf8))
        accumulator.append(Data("second stderr chunk".utf8))

        XCTAssertEqual(accumulator.stringValue(), "first stderr chunk\nsecond stderr chunk")
    }

    private func makePayload(provider: AiProvider, rawModelID: String) throws -> AiChatProviderRequestPayload {
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
            thinking: nil,
        )
    }
}

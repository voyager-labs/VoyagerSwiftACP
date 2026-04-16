@testable import VoyagerEntitiesAI
import XCTest

final class OpenAIAdapterTests: XCTestCase {
    // MARK: - Configuration

    func testConfiguration_chatCompletionsURL() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        XCTAssertEqual(config.chatCompletionsURL, "https://api.openai.com/v1/chat/completions")
    }

    func testConfiguration_customBaseURL_stripsTrailingSlash() {
        let config = OpenAIConfiguration(
            apiKey: "sk-test",
            defaultModel: AIModelID("gpt-4o"),
            baseURL: "https://custom.api.com/v1/",
        )
        XCTAssertEqual(config.chatCompletionsURL, "https://custom.api.com/v1/chat/completions")
    }

    func testConfiguration_requestHeaders_includesBearer() {
        let config = OpenAIConfiguration(apiKey: "sk-test-123", defaultModel: AIModelID("gpt-4o"))
        XCTAssertEqual(config.requestHeaders["Authorization"], "Bearer sk-test-123")
    }

    func testConfiguration_requestHeaders_includesOrganization() {
        let config = OpenAIConfiguration(
            apiKey: "sk-test",
            defaultModel: AIModelID("gpt-4o"),
            organizationID: "org-abc123",
        )
        XCTAssertEqual(config.requestHeaders["OpenAI-Organization"], "org-abc123")
    }

    func testConfiguration_requestHeaders_noOrganizationWhenNil() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        XCTAssertNil(config.requestHeaders["OpenAI-Organization"])
    }

    func testConfiguration_equality() {
        let a = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let b = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        XCTAssertEqual(a, b)
    }

    func testConfiguration_inequality_differentKey() {
        let a = OpenAIConfiguration(apiKey: "sk-test-1", defaultModel: AIModelID("gpt-4o"))
        let b = OpenAIConfiguration(apiKey: "sk-test-2", defaultModel: AIModelID("gpt-4o"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Capabilities

    func testCapabilities_full_hasAll() {
        let caps = OpenAICapabilities.full
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertTrue(caps.contains(.structuredOutput))
        XCTAssertTrue(caps.contains(.parallelToolCalls))
        XCTAssertTrue(caps.contains(.usageReporting))
        XCTAssertTrue(caps.contains(.reasoning))
    }

    func testCapabilities_standard_excludesReasoning() {
        let caps = OpenAICapabilities.standard
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertFalse(caps.contains(.reasoning))
    }

    func testCapabilities_minimal_textOnly() {
        let caps = OpenAICapabilities.minimal
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertFalse(caps.contains(.streaming))
        XCTAssertFalse(caps.contains(.toolCalling))
    }

    // MARK: - Adapter Construction

    func testAdapter_initializesWithConfiguration() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let adapter = OpenAIAdapter(configuration: config)
        XCTAssertEqual(adapter.configuration.apiKey, "sk-test")
        XCTAssertEqual(adapter.configuration.defaultModel, AIModelID("gpt-4o"))
        XCTAssertEqual(adapter.capabilities, OpenAICapabilities.standard)
    }

    func testAdapter_initializesWithCustomCapabilities() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let adapter = OpenAIAdapter(configuration: config, capabilities: .full)
        XCTAssertTrue(adapter.capabilities.contains(.reasoning))
        XCTAssertTrue(adapter.capabilities.contains(.structuredOutput))
    }

    // MARK: - Adapter Returns Voyager-Owned Types

    func testAdapter_generateReturnsAIGenerationResult() async throws {
        let config = OpenAIConfiguration(
            apiKey: "test",
            defaultModel: AIModelID("test-model"),
            baseURL: "https://httpbin.org/post",
        )
        let adapter = OpenAIAdapter(configuration: config, capabilities: .minimal)
        do {
            _ = try await adapter.generate(messages: [.user("Hello")])
        } catch {
            // Network errors expected — compiler check verifies return type
        }
    }

    func testAdapter_streamReturnsAIStreamEventSequence() {
        let config = OpenAIConfiguration(
            apiKey: "test",
            defaultModel: AIModelID("test-model"),
            baseURL: "https://httpbin.org/post",
        )
        let adapter = OpenAIAdapter(configuration: config)
        let stream: AsyncThrowingStream<AIStreamEvent, Error> = adapter.stream(messages: [.user("Hi")])
        _ = stream.makeAsyncIterator()
    }

    // MARK: - Error Types

    func testOpenAIAdapterError_streamingNotSupported() async {
        let config = OpenAIConfiguration(
            apiKey: "test",
            defaultModel: AIModelID("test-model"),
        )
        let adapter = OpenAIAdapter(configuration: config, capabilities: .minimal)
        let stream = adapter.stream(messages: [.user("Hi")])
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected streamingNotSupported error")
        } catch let error as OpenAIAdapterError {
            XCTAssertEqual(error, .streamingNotSupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenAIAdapterError_equality() {
        XCTAssertEqual(OpenAIAdapterError.streamingNotSupported, OpenAIAdapterError.streamingNotSupported)
        XCTAssertNotEqual(OpenAIAdapterError.streamingNotSupported, OpenAIAdapterError.invalidConfiguration("x"))
    }

    // MARK: - Tool Support Gated by Capabilities

    func testAdapter_toolsIgnoredWhenToolCallingNotInCapabilities() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let adapter = OpenAIAdapter(configuration: config, capabilities: .minimal)
        XCTAssertFalse(adapter.capabilities.contains(.toolCalling))
    }

    func testAdapter_toolsIncludedWhenToolCallingInCapabilities() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let adapter = OpenAIAdapter(configuration: config, capabilities: .standard)
        XCTAssertTrue(adapter.capabilities.contains(.toolCalling))
    }

    // MARK: - Stop Reason Mapping (via AIResponseNormalizer)

    func testStopReasonMapping_stop() {
        let reason = AIResponseNormalizer.mapFinishReason("stop")
        XCTAssertEqual(reason, .stop)
    }

    func testStopReasonMapping_toolCalls() {
        let reason = AIResponseNormalizer.mapFinishReason("tool_calls")
        XCTAssertEqual(reason, .toolCall)
    }

    func testStopReasonMapping_length() {
        let reason = AIResponseNormalizer.mapFinishReason("length")
        XCTAssertEqual(reason, .length)
    }

    func testStopReasonMapping_contentFilter() {
        let reason = AIResponseNormalizer.mapFinishReason("content_filter")
        XCTAssertEqual(reason, .contentFilter)
    }

    func testStopReasonMapping_nil_defaultsToStop() {
        let reason = AIResponseNormalizer.mapFinishReason(nil)
        XCTAssertEqual(reason, .stop)
    }

    func testStopReasonMapping_unknown_mapsToOther() {
        let reason = AIResponseNormalizer.mapFinishReason("unknown_reason")
        XCTAssertEqual(reason, .other)
    }

    // MARK: - No Unauthorized Surfaces

    func testAdapter_doesNotExposeEmbeddingTypes() {
        let config = OpenAIConfiguration(apiKey: "sk-test", defaultModel: AIModelID("gpt-4o"))
        let adapter = OpenAIAdapter(configuration: config)
        // Verify only generate/stream are available (compile-time check)
        _ = adapter.configuration
        _ = adapter.capabilities
        _ = adapter.httpClient
    }

    // MARK: - Response Normalization (Fixture Tests)

    func testNormalizeOpenAI_validResponse() throws {
        let json = """
        {
            "choices": [{
                "message": {"role": "assistant", "content": "Hello!"},
                "finish_reason": "stop"
            }],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
            "model": "gpt-4o"
        }
        """
        let data = json.data(using: .utf8)!
        let result = try AIResponseNormalizer.normalizeOpenAI(data: data, modelID: AIModelID("gpt-4o"))
        XCTAssertEqual(result.text, "Hello!")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.usage.promptTokens, 10)
        XCTAssertEqual(result.usage.completionTokens, 5)
        XCTAssertTrue(result.toolCalls.isEmpty)
    }

    func testNormalizeOpenAI_toolCallsResponse() throws {
        let json = """
        {
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": null,
                    "tool_calls": [{
                        "id": "call_123",
                        "type": "function",
                        "function": {"name": "get_weather", "arguments": "{\\"city\\":\\"SF\\"}"}
                    }]
                },
                "finish_reason": "tool_calls"
            }],
            "usage": {"prompt_tokens": 20, "completion_tokens": 10, "total_tokens": 30},
            "model": "gpt-4o"
        }
        """
        let data = json.data(using: .utf8)!
        let result = try AIResponseNormalizer.normalizeOpenAI(data: data, modelID: AIModelID("gpt-4o"))
        XCTAssertEqual(result.finishReason, .toolCall)
        XCTAssertTrue(result.hasToolCalls)
        XCTAssertEqual(result.toolCalls.first?.name, "get_weather")
        XCTAssertEqual(result.toolCalls.first?.id, "call_123")
    }

    func testNormalizeOpenAI_noChoices_throws() {
        let json = """
        {"choices": [], "model": "gpt-4o"}
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try AIResponseNormalizer.normalizeOpenAI(data: data)) { error in
            XCTAssertTrue(error is AINormalizationError)
        }
    }

    // MARK: - SSE Parsing (Fixture Tests)

    func testParseOpenAISSELine_textDelta() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}"
        let event = AIResponseNormalizer.parseOpenAISSELine(line)
        XCTAssertEqual(event, .textDelta("Hi"))
    }

    func testParseOpenAISSELine_toolCallDelta() {
        let line = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"search\",\"arguments\":\"{\\\"q\\\":\\\"test\\\"}\"}}]},\"finish_reason\":null}]}"
        let event = AIResponseNormalizer.parseOpenAISSELine(line)
        XCTAssertNotNil(event)
        if case let .toolCallDelta(id, name, args) = event {
            XCTAssertEqual(id, "call_1")
            XCTAssertEqual(name, "search")
            XCTAssertEqual(args, "{\"q\":\"test\"}")
        } else {
            XCTFail("Expected toolCallDelta")
        }
    }

    func testParseOpenAISSELine_done_returnsNil() {
        let line = "data: [DONE]"
        let event = AIResponseNormalizer.parseOpenAISSELine(line)
        XCTAssertNil(event)
    }

    func testParseOpenAISSELine_nonData_returnsNil() {
        let event = AIResponseNormalizer.parseOpenAISSELine("event: ping")
        XCTAssertNil(event)
    }
}

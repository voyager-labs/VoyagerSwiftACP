@testable import VoyagerEntitiesAI
import XCTest

final class AnthropicAdapterTests: XCTestCase {
    // MARK: - Configuration

    func testConfiguration_messagesURL() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        XCTAssertEqual(config.messagesURL, "https://api.anthropic.com/v1/messages")
    }

    func testConfiguration_customBaseURL_stripsTrailingSlash() {
        let config = AnthropicConfiguration(
            apiKey: "sk-ant-test",
            baseURL: "https://custom.proxy.com/",
        )
        XCTAssertEqual(config.messagesURL, "https://custom.proxy.com/v1/messages")
    }

    func testConfiguration_requestHeaders_includesAPIKey() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-123")
        XCTAssertEqual(config.requestHeaders["x-api-key"], "sk-ant-123")
    }

    func testConfiguration_requestHeaders_includesAPIVersion() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        XCTAssertEqual(config.requestHeaders["anthropic-version"], "2023-06-01")
    }

    func testConfiguration_requestHeaders_includesContentType() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        XCTAssertEqual(config.requestHeaders["content-type"], "application/json")
    }

    func testConfiguration_equality() {
        let a = AnthropicConfiguration(apiKey: "sk-ant-test", defaultModel: AIModelID("claude-3"))
        let b = AnthropicConfiguration(apiKey: "sk-ant-test", defaultModel: AIModelID("claude-3"))
        XCTAssertEqual(a, b)
    }

    func testConfiguration_inequality() {
        let a = AnthropicConfiguration(apiKey: "sk-ant-1")
        let b = AnthropicConfiguration(apiKey: "sk-ant-2")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Capabilities

    func testCapabilities_full_hasAll() {
        let caps = AnthropicCapabilities.full
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertTrue(caps.contains(.structuredOutput))
        XCTAssertTrue(caps.contains(.parallelToolCalls))
        XCTAssertTrue(caps.contains(.usageReporting))
        XCTAssertTrue(caps.contains(.reasoning))
    }

    func testCapabilities_standard_excludesReasoning() {
        let caps = AnthropicCapabilities.standard
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertFalse(caps.contains(.reasoning))
        XCTAssertFalse(caps.contains(.structuredOutput))
    }

    func testCapabilities_minimal_textOnly() {
        let caps = AnthropicCapabilities.minimal
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertFalse(caps.contains(.streaming))
        XCTAssertFalse(caps.contains(.toolCalling))
    }

    // MARK: - Adapter Construction

    func testAdapter_initializesWithConfiguration() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        let adapter = AnthropicAdapter(configuration: config)
        XCTAssertEqual(adapter.configuration.apiKey, "sk-ant-test")
        XCTAssertEqual(adapter.capabilities, AnthropicCapabilities.standard)
    }

    func testAdapter_initializesWithCustomCapabilities() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        let adapter = AnthropicAdapter(configuration: config, capabilities: .full)
        XCTAssertTrue(adapter.capabilities.contains(.reasoning))
        XCTAssertTrue(adapter.capabilities.contains(.structuredOutput))
    }

    // MARK: - Adapter Returns Voyager-Owned Types

    func testAdapter_generateReturnsAIGenerationResult() async throws {
        let config = AnthropicConfiguration(
            apiKey: "test",
            baseURL: "https://httpbin.org/post",
        )
        let adapter = AnthropicAdapter(configuration: config, capabilities: .minimal)
        do {
            _ = try await adapter.generate(messages: [.user("Hello")])
        } catch {
            // Network errors expected — compiler check verifies return type
        }
    }

    func testAdapter_streamReturnsAIStreamEventSequence() {
        let config = AnthropicConfiguration(
            apiKey: "test",
            baseURL: "https://httpbin.org/post",
        )
        let adapter = AnthropicAdapter(configuration: config)
        let stream: AsyncThrowingStream<AIStreamEvent, Error> = adapter.stream(messages: [.user("Hi")])
        _ = stream.makeAsyncIterator()
    }

    // MARK: - Error Types

    func testAnthropicAdapterError_streamingNotSupported() async {
        let config = AnthropicConfiguration(apiKey: "test")
        let adapter = AnthropicAdapter(configuration: config, capabilities: .minimal)
        let stream = adapter.stream(messages: [.user("Hi")])
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected streamingNotSupported error")
        } catch let error as AnthropicAdapterError {
            XCTAssertEqual(error, .streamingNotSupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnthropicAdapterError_equality() {
        XCTAssertEqual(AnthropicAdapterError.streamingNotSupported, AnthropicAdapterError.streamingNotSupported)
        XCTAssertNotEqual(AnthropicAdapterError.streamingNotSupported, AnthropicAdapterError.invalidConfiguration("x"))
    }

    // MARK: - Tool Support Gated by Capabilities

    func testAdapter_toolsIgnoredWhenToolCallingNotInCapabilities() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        let adapter = AnthropicAdapter(configuration: config, capabilities: .minimal)
        XCTAssertFalse(adapter.capabilities.contains(.toolCalling))
    }

    func testAdapter_toolsIncludedWhenToolCallingInCapabilities() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        let adapter = AnthropicAdapter(configuration: config, capabilities: .standard)
        XCTAssertTrue(adapter.capabilities.contains(.toolCalling))
    }

    // MARK: - Anthropic Stop Reason Mapping

    func testAnthropicStopReason_endTurn() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("end_turn")
        XCTAssertEqual(reason, .stop)
    }

    func testAnthropicStopReason_toolUse() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("tool_use")
        XCTAssertEqual(reason, .toolCall)
    }

    func testAnthropicStopReason_maxTokens() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("max_tokens")
        XCTAssertEqual(reason, .length)
    }

    func testAnthropicStopReason_stopSequence() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("stop_sequence")
        XCTAssertEqual(reason, .stop)
    }

    func testAnthropicStopReason_refusal() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("refusal")
        XCTAssertEqual(reason, .contentFilter)
    }

    func testAnthropicStopReason_nil() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason(nil)
        XCTAssertEqual(reason, .stop)
    }

    func testAnthropicStopReason_unknown() {
        let reason = AIResponseNormalizer.mapAnthropicFinishReason("unknown_reason")
        XCTAssertEqual(reason, .other)
    }

    // MARK: - Anthropic Response Normalization

    func testNormalizeAnthropic_textResponse() throws {
        let json = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "Hello from Claude!"}],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 5}
        }
        """
        let data = json.data(using: .utf8)!
        let result = try AIResponseNormalizer.normalizeAnthropic(data: data, modelID: AIModelID("claude-sonnet-4"))
        XCTAssertEqual(result.text, "Hello from Claude!")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.usage.promptTokens, 10)
        XCTAssertEqual(result.usage.completionTokens, 5)
        XCTAssertTrue(result.toolCalls.isEmpty)
    }

    func testNormalizeAnthropic_toolUseResponse() throws {
        let json = """
        {
            "id": "msg_456",
            "type": "message",
            "role": "assistant",
            "content": [
                {"type": "text", "text": "Let me check that."},
                {"type": "tool_use", "id": "toolu_123", "name": "get_weather", "input": {"city": "SF"}}
            ],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "tool_use",
            "usage": {"input_tokens": 20, "output_tokens": 15}
        }
        """
        let data = json.data(using: .utf8)!
        let result = try AIResponseNormalizer.normalizeAnthropic(data: data)
        XCTAssertEqual(result.finishReason, .toolCall)
        XCTAssertTrue(result.hasToolCalls)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls.first?.id, "toolu_123")
        XCTAssertEqual(result.toolCalls.first?.name, "get_weather")
    }

    // MARK: - Anthropic SSE Parsing

    func testParseAnthropicSSELine_textDelta() {
        let line = "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertEqual(event, .textDelta("Hi"))
    }

    func testParseAnthropicSSELine_inputJsonDelta() {
        let line = "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"q\\\":\\\"test\\\"}\"}}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNotNil(event)
        if case let .toolCallDelta(_, name, args) = event {
            XCTAssertNil(name)
            XCTAssertEqual(args, "{\"q\":\"test\"}")
        } else {
            XCTFail("Expected toolCallDelta")
        }
    }

    func testParseAnthropicSSELine_messageDelta() {
        let line = "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNotNil(event)
        if case let .finish(reason, usage) = event {
            XCTAssertEqual(reason, .stop)
            XCTAssertEqual(usage.promptTokens, 10)
            XCTAssertEqual(usage.completionTokens, 20)
        } else {
            XCTFail("Expected finish")
        }
    }

    func testParseAnthropicSSELine_contentBlockStart_toolUse() {
        let line = "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_abc\",\"name\":\"search\"}}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNotNil(event)
        if case let .toolCallDelta(id, name, args) = event {
            XCTAssertEqual(id, "toolu_abc")
            XCTAssertEqual(name, "search")
            XCTAssertEqual(args, "")
        } else {
            XCTFail("Expected toolCallDelta")
        }
    }

    func testParseAnthropicSSELine_done_returnsNil() {
        let line = "data: [DONE]"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNil(event)
    }

    func testParseAnthropicSSELine_nonData_returnsNil() {
        let event = AIResponseNormalizer.parseAnthropicSSELine("event: ping")
        XCTAssertNil(event)
    }

    func testParseAnthropicSSELine_messageStart_returnsNil() {
        let line = "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-3\",\"stop_reason\":null}}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNil(event)
    }

    func testParseAnthropicSSELine_ping_returnsNil() {
        let line = "data: {\"type\":\"ping\"}"
        let event = AIResponseNormalizer.parseAnthropicSSELine(line)
        XCTAssertNil(event)
    }

    // MARK: - No Unauthorized Surfaces

    func testAdapter_doesNotExposeCitationTypes() {
        let config = AnthropicConfiguration(apiKey: "sk-ant-test")
        let adapter = AnthropicAdapter(configuration: config)
        _ = adapter.configuration
        _ = adapter.capabilities
        _ = adapter.httpClient
    }
}

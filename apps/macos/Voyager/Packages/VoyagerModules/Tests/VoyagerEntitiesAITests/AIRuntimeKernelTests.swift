@testable import VoyagerEntitiesAI
import XCTest

final class AIRuntimeKernelTests: XCTestCase {
    // MARK: - ServerSentEventParser

    func testSSEParser_simpleMessage() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("data: Hello, world!")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "Hello, world!")
        XCTAssertNil(events[0].event)
        XCTAssertNil(events[0].id)
    }

    func testSSEParser_eventWithType() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("event: tool_call")
        XCTAssertEqual(events.count, 0)

        let events2 = parser.ingestLine("data: {\"name\":\"getWeather\"}")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].event, "tool_call")
        XCTAssertEqual(events2[0].data, "{\"name\":\"getWeather\"}")
    }

    func testSSEParser_multipleDataLines() {
        var parser = ServerSentEventParser()

        _ = parser.ingestLine("data: line one")
        let events = parser.ingestLine("data: line two")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "line one\nline two")
    }

    func testSSEParser_eventWithID() {
        var parser = ServerSentEventParser()

        _ = parser.ingestLine("id: 123")
        let events = parser.ingestLine("data: hello")
        XCTAssertEqual(events[0].id, "123")
    }

    func testSSEParser_commentIgnored() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine(": this is a comment")
        XCTAssertEqual(events.count, 0)
    }

    func testSSEParser_emptyLineDispatches() {
        var parser = ServerSentEventParser()

        _ = parser.ingestLine("data: first event")
        let events = parser.ingestLine("")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "first event")
    }

    func testSSEParser_retryField() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("retry: 5000")
        XCTAssertEqual(events.count, 0)
        let finishEvents = parser.finish()
        XCTAssertTrue(finishEvents.isEmpty)
    }

    func testSSEParser_finishWithPendingData() {
        var parser = ServerSentEventParser()

        _ = parser.ingestLine("data: pending")
        let events = parser.finish()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "pending")
    }

    func testSSEParser_crlfHandling() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("data: test\r")
        XCTAssertEqual(events.count, 0)

        let events2 = parser.ingestLine("")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].data, "test")
    }

    func testSSEParser_bomStripping() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("data: \u{FEFF}hello")
        XCTAssertEqual(events.count, 0)

        let events2 = parser.ingestLine("")
        XCTAssertEqual(events2[0].data, "hello")
    }

    func testSSEParser_keepAlive() {
        var parser = ServerSentEventParser()

        let events = parser.ingestLine("id: 42")
        XCTAssertEqual(events.count, 0)

        let events2 = parser.ingestLine("")
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2[0].id, "42")
        XCTAssertEqual(events2[0].data, "")
    }

    // MARK: - AIJSONSchema

    func testJSONSchema_stringType() {
        struct Params: Codable, Sendable { let name: String }
        let schema = AIJSONSchema.generate(for: Params.self)
        XCTAssertEqual(schema["type"] as? String, "object")
        let props = schema["properties"] as? [String: Any]
        XCTAssertEqual(props?["name"] as? String, "string")
    }

    func testJSONSchema_multipleTypes() {
        struct Params: Codable, Sendable {
            let name: String
            let age: Int
            let active: Bool
        }
        let schema = AIJSONSchema.generate(for: Params.self)
        let props = schema["properties"] as? [String: Any]
        XCTAssertEqual(props?["name"] as? String, "string")
        XCTAssertEqual(props?["age"] as? String, "integer")
        XCTAssertEqual(props?["active"] as? String, "boolean")
    }

    func testJSONSchema_requiredFields() {
        struct Params: Codable, Sendable {
            let requiredField: String
            let optionalField: String?
        }
        let schema = AIJSONSchema.generate(for: Params.self)
        let required = schema["required"] as? [String]
        XCTAssertTrue(required?.contains("requiredField") ?? false)
        XCTAssertFalse(required?.contains("optionalField") ?? true)
    }

    func testJSONSchema_arrayType() {
        struct Params: Codable, Sendable {
            let items: [String]
        }
        let schema = AIJSONSchema.generate(for: Params.self)
        let props = schema["properties"] as? [String: Any]
        let items = props?["items"] as? [String: Any]
        XCTAssertEqual(items?["type"] as? String, "array")
        let itemsSchema = items?["items"] as? [String: Any]
        XCTAssertEqual(itemsSchema?["type"] as? String, "string")
    }

    func testJSONSchema_optionalInt() {
        struct Params: Codable, Sendable {
            let count: Int?
        }
        let schema = AIJSONSchema.generate(for: Params.self)
        let props = schema["properties"] as? [String: Any]
        XCTAssertEqual(props?["count"] as? String, "integer")
        let required = schema["required"] as? [String]
        XCTAssertFalse(required?.contains("count") ?? false)
    }

    // MARK: - AIHTTPClient

    func testAHTTPClient_invalidURL() async {
        let client = AIHTTPClient()
        do {
            _ = try await client.post(url: "not-a-valid-url", body: ["key": "value"])
            XCTFail("Expected error")
        } catch let error as AIHTTPError {
            XCTAssertEqual(error, .invalidURL("not-a-valid-url"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAITimeoutDefaults() {
        XCTAssertEqual(AITimeoutDefaults.connect, 60)
        XCTAssertEqual(AITimeoutDefaults.total, 120)
    }

    // MARK: - AIRequestBuilder

    func testAIRequestBuilder_chatRequest() throws {
        let result = try AIRequestBuilder.shared.buildChatRequest(
            url: "https://api.example.com/chat",
            apiKey: "test-key",
            model: "gpt-4o",
            messages: [.user("Hello")],
        )

        XCTAssertEqual(result.url, "https://api.example.com/chat")
        XCTAssertEqual(result.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(result.body.model, "gpt-4o")
        XCTAssertEqual(result.body.messages.count, 1)
        XCTAssertEqual(result.body.messages[0].role, "user")
    }

    func testAIRequestBuilder_withTools() throws {
        let tool = AIToolDefinition(
            name: "getWeather",
            description: "Get weather for a city",
            parameters: ["city": AnyCodableValue("string")],
        )

        let result = try AIRequestBuilder.shared.buildChatRequest(
            url: "https://api.example.com/chat",
            apiKey: "test-key",
            model: "gpt-4o",
            messages: [.user("Weather?")],
            tools: [tool],
        )

        XCTAssertNotNil(result.body.tools)
        XCTAssertEqual(result.body.tools?.count, 1)
    }

    func testAIRequestBuilder_streaming() throws {
        let result = try AIRequestBuilder.shared.buildChatRequest(
            url: "https://api.example.com/chat",
            apiKey: "test-key",
            model: "gpt-4o",
            messages: [.user("Hello")],
            stream: true,
        )
        XCTAssertTrue(result.body.stream)
    }

    func testAIRequestBuilder_authHeaders() {
        let headers = AIRequestBuilder.shared.buildAuthHeaders(apiKey: "my-key")
        XCTAssertEqual(headers["Authorization"], "Bearer my-key")
    }

    // MARK: - AIToolExecutor

    func testAIToolExecutor_registerAndExecute() async throws {
        struct FakeTool: AITool {
            let name = "echo"
            let description = "Echoes the input"
            let inputSchema: [String: Any]? = nil
            func execute(arguments: String) async throws -> String {
                "echo: \(arguments)"
            }
        }

        let executor = AIToolExecutor()
        executor.register(FakeTool())

        let result = try await executor.execute(toolCall: AIToolCall(
            id: "1",
            name: "echo",
            arguments: "\"hello\"",
        ))

        XCTAssertEqual(result.id, "1")
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.content, "echo: \"hello\"")
    }

    func testAIToolExecutor_toolNotFound() async {
        let executor = AIToolExecutor()

        do {
            _ = try await executor.execute(toolCall: AIToolCall(
                id: "99",
                name: "nonexistent",
                arguments: "{}",
            ))
            XCTFail("Expected error")
        } catch let error as AIToolExecutionError {
            XCTAssertEqual(error, .toolNotFound("nonexistent"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAIToolExecutor_unregister() async {
        struct FakeTool: AITool {
            let name = "testTool"
            let description = ""
            let inputSchema: [String: Any]? = nil
            func execute(arguments _: String) async throws -> String { "" }
        }

        let executor = AIToolExecutor()
        executor.register(FakeTool())
        XCTAssertTrue(executor.unregister(name: "testTool"))
        XCTAssertFalse(executor.unregister(name: "testTool"))
    }

    func testAIToolExecutor_parallelExecution() async throws {
        struct DelayTool: AITool {
            let name: String
            let delayMs: Int
            var description: String { "" }
            var inputSchema: [String: Any]? { nil }
            func execute(arguments: String) async throws -> String {
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                return "\(name):\(arguments)"
            }
        }

        let executor = AIToolExecutor()
        executor.register(DelayTool(name: "slow1", delayMs: 20))
        executor.register(DelayTool(name: "slow2", delayMs: 20))

        let results = try await executor.execute(toolCalls: [
            AIToolCall(id: "1", name: "slow1", arguments: "a"),
            AIToolCall(id: "2", name: "slow2", arguments: "b"),
        ])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "1")
        XCTAssertEqual(results[1].id, "2")
    }

    // MARK: - AIResponseNormalizer

    func testNormalizer_openAIResponse() throws {
        let json = """
        {
            "model": "gpt-4o",
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": "Hello!"
                },
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15
            }
        }
        """.data(using: .utf8)!

        let result = try AIResponseNormalizer.normalizeOpenAI(data: json)

        XCTAssertEqual(result.text, "Hello!")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.usage.promptTokens, 10)
        XCTAssertEqual(result.usage.completionTokens, 5)
        XCTAssertEqual(result.usage.totalTokens, 15)
    }

    func testNormalizer_openAIWithToolCalls() throws {
        let json = """
        {
            "model": "gpt-4o",
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": null,
                    "tool_calls": [{
                        "id": "call_1",
                        "type": "function",
                        "function": {
                            "name": "getWeather",
                            "arguments": "{\\"city\\":\\"Seoul\\"}"
                        }
                    }]
                },
                "finish_reason": "tool_calls"
            }],
            "usage": { "prompt_tokens": 5, "completion_tokens": 10, "total_tokens": 15 }
        }
        """.data(using: .utf8)!

        let result = try AIResponseNormalizer.normalizeOpenAI(data: json)

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.finishReason, .toolCall)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].id, "call_1")
        XCTAssertEqual(result.toolCalls[0].name, "getWeather")
        XCTAssertTrue(result.toolCalls[0].arguments.contains("Seoul"))
    }

    func testNormalizer_openAI_noChoices() {
        let json = """
        {"choices": []}
        """.data(using: .utf8)!

        do {
            _ = try AIResponseNormalizer.normalizeOpenAI(data: json)
            XCTFail("Expected error")
        } catch AINormalizationError.noChoices {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func testNormalizer_parseSSELine_textDelta() {
        let event = AIResponseNormalizer.parseOpenAISSELine(
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
        )

        if case let .textDelta(text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected textDelta, got \(String(describing: event))")
        }
    }

    func testNormalizer_parseSSELine_toolCallDelta() {
        let event = AIResponseNormalizer.parseOpenAISSELine(
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"weather\",\"arguments\":\"{\\\"city\\\":\\\"NY\\\"}\"}}]}}]}",
        )

        if case let .toolCallDelta(id, name, args) = event {
            XCTAssertEqual(id, "c1")
            XCTAssertEqual(name, "weather")
            XCTAssertTrue(args.contains("NY"))
        } else {
            XCTFail("Expected toolCallDelta, got \(String(describing: event))")
        }
    }

    func testNormalizer_parseSSELine_dismiss() {
        XCTAssertNil(AIResponseNormalizer.parseOpenAISSELine("data: [DONE]"))
        XCTAssertNil(AIResponseNormalizer.parseOpenAISSELine(""))
        XCTAssertNil(AIResponseNormalizer.parseOpenAISSELine("not data prefix"))
    }

    func testNormalizer_mapFinishReason() {
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason("stop"), .stop)
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason("tool_calls"), .toolCall)
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason("length"), .length)
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason("content_filter"), .contentFilter)
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason("unknown"), .other)
        XCTAssertEqual(AIResponseNormalizer.mapFinishReason(nil), .stop)
    }

    // MARK: - AIToolCall Codable Round-Trip

    func testAIToolCall_codableRoundTrip() throws {
        let original = AIToolCall(id: "call-123", name: "getWeather", arguments: "{\"city\":\"Seoul\"}")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIToolCall.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.arguments, original.arguments)
    }

    func testAIGenerationResult_codableRoundTrip() throws {
        let original = AIGenerationResult(
            text: "Hello world",
            finishReason: .stop,
            usage: AIUsage(promptTokens: 5, completionTokens: 3),
            toolCalls: [],
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIGenerationResult.self, from: data)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.finishReason, original.finishReason)
        XCTAssertEqual(decoded.usage.promptTokens, 5)
    }

    func testAIStreamEvent_codableRoundTrip() throws {
        let event = AIStreamEvent.textDelta("Hello")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)

        if case let .textDelta(text) = decoded {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected textDelta")
        }
    }
}

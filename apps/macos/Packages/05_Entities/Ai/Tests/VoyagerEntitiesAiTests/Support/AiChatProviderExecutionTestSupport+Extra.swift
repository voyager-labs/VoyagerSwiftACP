@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

private struct ProviderExecutionCapturedOpenAIRequestBody: Decodable {
    let model: String
    let input: [ProviderExecutionCapturedOpenAIInputItem]
    let reasoning: ProviderExecutionCapturedOpenAIReasoning?
    let stream: Bool
}

private struct ProviderExecutionCapturedOpenAIInputItem: Decodable {
    let role: String
    let content: ProviderExecutionCapturedOpenAIContent
}

private enum ProviderExecutionCapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([ProviderExecutionCapturedOpenAIContentItem])

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [ProviderExecutionCapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .parts(container.decode([ProviderExecutionCapturedOpenAIContentItem].self))
    }
}

private struct ProviderExecutionCapturedOpenAIContentItem: Decodable, Equatable {
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

private struct ProviderExecutionCapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

private struct ProviderExecutionCapturedAnthropicRequestBody: Decodable {
    let model: String
    let maxTokens: Int
    let messages: [ProviderExecutionCapturedAnthropicMessage]
    let system: String?
    let thinking: ProviderExecutionCapturedAnthropicThinking?
    let outputConfig: ProviderExecutionCapturedAnthropicOutputConfig?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case thinking
        case outputConfig = "output_config"
        case stream
    }
}

private struct ProviderExecutionCapturedAnthropicOutputConfig: Decodable {
    let effort: String?
}

private struct ProviderExecutionCapturedAnthropicMessage: Decodable {
    let role: String
    let content: [ProviderExecutionCapturedAnthropicContentItem]
}

private struct ProviderExecutionCapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: ProviderExecutionCapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

private struct ProviderExecutionCapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct ProviderExecutionCapturedAnthropicThinking: Decodable {
    let type: String
    let budgetTokens: Int?
    let display: String?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
        case display
    }
}

enum ProviderExecutionExpectedAnthropicThinking: Equatable {
    case disabled
    case enabled(Int, display: String?)
    case outputConfigEffort(String)
    case adaptive(String, display: String?)
    case omitted
}

final class ProviderExecutionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var currentHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { currentHandler }
        set { currentHandler = newValue }
    }

    static var requestCount: Int {
        count
    }

    static func reset() {
        count = 0
        currentHandler = nil
    }

    override static func canInit(with _: URLRequest) -> Bool {
        count += 1
        return true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func providerExecutionAssertOpenAIRequest(_ request: URLRequest, expectedModel: String) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(providerExecutionRequestBodyData(for: request))
    let decoded = try JSONDecoder().decode(ProviderExecutionCapturedOpenAIRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.reasoning?.effort, "high")
    XCTAssertEqual(decoded.input.map(\.role), ["developer", "developer", "user", "assistant"])
    let prompt = decoded.input.first?.content.text
    XCTAssertEqual(prompt?.contains("current_context:"), true)
    XCTAssertEqual(prompt?.contains("summary: locked workspace context"), true)
    XCTAssertEqual(prompt?.contains("Notes.txt [resolvedText]"), true)
    XCTAssertEqual(prompt?.contains("Attachment body from locked snapshot"), true)
    XCTAssertEqual(prompt?.contains("Workspace.voycoll [resolvedReference]"), true)
    XCTAssertEqual(prompt?.contains("reference included; content not expanded."), true)
    XCTAssertEqual(prompt?.contains("Large.bin [tooLarge]"), true)
    XCTAssertEqual(prompt?.contains("not included: tooLarge"), true)
    XCTAssertEqual(prompt?.contains("Unsupported.bin [unsupportedType]"), true)
    XCTAssertEqual(prompt?.contains("not included: unsupportedType"), true)
    XCTAssertEqual(prompt?.contains("live workspace context"), false)
    XCTAssertEqual(prompt?.contains("Should not leak live attachment"), false)
    XCTAssertEqual(decoded.input[1].content.text, "System rule")
    XCTAssertEqual(decoded.input[2].content.text, "Hello")
    XCTAssertEqual(decoded.input[3].content.text, "Previous answer")
}

func providerExecutionAssertAnthropicRequest(
    _ request: URLRequest,
    expectedModel: String,
    expectedThinking: ProviderExecutionExpectedAnthropicThinking,
) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(providerExecutionRequestBodyData(for: request))
    let decoded = try JSONDecoder().decode(ProviderExecutionCapturedAnthropicRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertEqual(decoded.maxTokens, 4096)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.system?.contains("current_context:"), true)
    XCTAssertEqual(decoded.system?.contains("summary: locked workspace context"), true)
    XCTAssertEqual(decoded.system?.contains("Notes.txt [resolvedText]"), true)
    XCTAssertEqual(decoded.system?.contains("Workspace.voycoll [resolvedReference]"), true)
    XCTAssertEqual(decoded.system?.contains("Large.bin [tooLarge]"), true)
    XCTAssertEqual(decoded.system?.contains("Unsupported.bin [unsupportedType]"), true)
    XCTAssertEqual(decoded.system?.contains("live workspace context"), false)
    XCTAssertEqual(decoded.system?.contains("Answer briefly"), true)
    XCTAssertEqual(decoded.messages.map(\.role), ["user", "assistant"])
    XCTAssertEqual(decoded.messages.first?.content, [.text("Say hi")])
    XCTAssertEqual(decoded.messages.last?.content, [.text("Previous reply")])

    switch expectedThinking {
    case .disabled:
        XCTAssertEqual(decoded.thinking?.type, "disabled")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertNil(decoded.thinking?.display)
        XCTAssertNil(decoded.outputConfig)
    case let .enabled(budget, display):
        XCTAssertEqual(decoded.thinking?.type, "enabled")
        XCTAssertEqual(decoded.thinking?.budgetTokens, budget)
        XCTAssertEqual(decoded.thinking?.display, display)
        XCTAssertNil(decoded.outputConfig)
    case let .outputConfigEffort(effort):
        XCTAssertNil(decoded.thinking)
        XCTAssertEqual(decoded.outputConfig?.effort, effort)
    case let .adaptive(effort, display):
        XCTAssertEqual(decoded.thinking?.type, "adaptive")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertEqual(decoded.thinking?.display, display)
        XCTAssertEqual(decoded.outputConfig?.effort, effort)
    case .omitted:
        XCTAssertNil(decoded.thinking)
        XCTAssertNil(decoded.outputConfig)
    }
}

func providerExecutionRequestBodyData(for request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    defer { buffer.deallocate() }
    var data = Data()

    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: 1024)
        if read < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if read == 0 { break }
        data.append(buffer, count: read)
    }

    return data
}

func providerExecutionOpenAIStreamingBody() -> String {
    """
    event: response.created
    data: {"type":"response.created"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.output_text.done
    data: {"type":"response.output_text.done","text":"Hello"}

    event: response.completed
    data: {"type":"response.completed","response":{"output_text":"Hello"}}

    data: [DONE]

    """
}

func providerExecutionOpenAIStreamFailureBody() -> String {
    """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"partial"}

    event: response.failed
    data: {"type":"response.failed","error":{"message":"OpenAI stream failed"}}

    """
}

func providerExecutionOpenAIFinalOnlyBody() -> String {
    #"{"output":[{"content":[{"type":"output_text","text":"Hello"}]}]}"#
}

func providerExecutionAnthropicStreamingBody() -> String {
    """
    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

func providerExecutionAnthropicStreamingBodyWithThinkingAndMessageDelta() -> String {
    """
    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"internal reasoning"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Final"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" answer"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":861}}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

func providerExecutionAnthropicStreamErrorBody(type: String) -> String {
    """
    event: error
    data: {"type":"error","error":{"type":"\(type)","message":"anthropic stream failed"}}

    """
}

func providerExecutionAnthropicFinalOnlyBody() -> String {
    #"{"content":[{"type":"text","text":"Hi there"}],"stop_reason":"end_turn"}"#
}

func providerExecutionMakeHTTPResponse(
    statusCode: Int,
    contentType: String,
    body: String,
    url: String = "https://api.openai.com/v1/responses",
) -> (HTTPURLResponse, Data) {
    let resolvedURL = URL(string: url) ?? URL(fileURLWithPath: "/invalid-url")
    let response = HTTPURLResponse(
        url: resolvedURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": contentType],
    ) ?? HTTPURLResponse()
    return (response, Data(body.utf8))
}

func providerExecutionMakeUUID(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue) ?? UUID()
}

func providerExecutionCollect(
    _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
) throws -> [AiChatProviderExecutionEvent] {
    let expectation = XCTestExpectation(description: "Collect provider execution events")
    nonisolated(unsafe) var result: Result<[AiChatProviderExecutionEvent], Error>?

    Task { @Sendable in
        do {
            var events: [AiChatProviderExecutionEvent] = []
            for try await event in stream {
                events.append(event)
            }
            result = .success(events)
        } catch {
            result = .failure(error)
        }
        expectation.fulfill()
    }

    _ = XCTWaiter.wait(for: [expectation], timeout: 2.0)
    return try XCTUnwrap(result).get()
}

func providerExecutionStatus(
    _ context: AiChatRequestContextSnapshot,
    _ activityID: String,
    _ kind: AiChatExecutionActivityKind,
    _ phase: AiChatExecutionActivityPhase,
    _ providerEventType: String,
    origin: AiChatExecutionEvidenceOrigin = .providerWire,
    boundaryEventTypes: [String] = [],
) -> AiChatProviderExecutionEvent {
    .status(
        context: context,
        signal: AiChatExecutionActivitySignal(
            activityID: AiChatExecutionActivityID(rawValue: activityID),
            kind: kind,
            phase: phase,
            evidence: AiChatExecutionActivityEvidence(
                origin: origin,
                providerEventType: providerEventType,
                boundaryEventTypes: boundaryEventTypes,
            ),
        ),
    )
}

func providerExecutionOpenAITypedActivityBody() -> String {
    """
    data: {"type":"response.reasoning_summary_text.delta","item_id":"reason-1","delta":"summary"}

    data: {"type":"response.reasoning_summary_text.done","item_id":"reason-1","text":"summary"}

    data: {"type":"response.web_search_call.in_progress","item_id":"search-a"}

    data: {"type":"response.web_search_call.searching","item_id":"search-b"}

    data: {"type":"response.web_search_call.completed","item_id":"search-b"}

    data: {"type":"response.web_search_call.completed","item_id":"search-a"}

    data: {"type":"response.file_search_call.in_progress","item_id":"file-1"}

    data: {"type":"response.file_search_call.completed","item_id":"file-1"}

    data: {"type":"response.code_interpreter_call.in_progress","item_id":"code-1"}

    data: {"type":"response.code_interpreter_call.completed","item_id":"code-1"}

    data: {"type":"response.mcp_call.in_progress","item_id":"mcp-1"}

    data: {"type":"response.mcp_call.failed","item_id":"mcp-1"}

    data: {"type":"response.output_text.delta","item_id":"message-1","delta":"Hello"}

    data: {"type":"response.output_text.done","item_id":"message-1","text":"Hello"}

    data: {"type":"response.completed","response":{"output_text":"Hello"}}

    data: [DONE]

    """
}

func providerExecutionAnthropicTypedActivityBody() -> String {
    """
    data: {"type":"message_start","message":{"content":[]}}

    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"reason"}}

    data: {"type":"content_block_stop","index":0}

    data: {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srv-search","name":"web_search","input":{}}}

    data: {"type":"content_block_stop","index":1}

    data: {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srv-search","content":[]}}

    data: {"type":"content_block_stop","index":2}

    data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"client-tool","name":"local_tool","input":{}}}

    data: {"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{}"}}

    data: {"type":"content_block_stop","index":3}

    data: {"type":"content_block_start","index":4,"content_block":{"type":"server_tool_use","id":"srv-code","name":"code_execution","input":{}}}

    data: {"type":"content_block_stop","index":4}

    data: {"type":"content_block_start","index":5,"content_block":{"type":"code_execution_tool_result","tool_use_id":"srv-code","content":[]}}

    data: {"type":"content_block_stop","index":5}

    data: {"type":"content_block_start","index":7,"content_block":{"type":"text","text":""}}

    data: {"type":"content_block_delta","index":7,"delta":{"type":"text_delta","text":"Answer"}}

    data: {"type":"content_block_stop","index":7}

    data: {"type":"message_stop"}

    """
}

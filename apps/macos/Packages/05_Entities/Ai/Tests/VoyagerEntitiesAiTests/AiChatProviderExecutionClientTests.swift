// swiftlint:disable file_length
@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

// swiftlint:disable:next type_body_length
final class AiChatProviderExecutionClientTests: XCTestCase {
    override func tearDown() {
        OpenAIExecutionURLProtocol.reset()
        super.tearDown()
    }

    func testExecute_openAIWithOAuthCredential_failsBeforeNetwork() throws {
        let client = makeLiveClient()
        let request = makeRequest(provider: .openai, rawModelID: "gpt-5.5")

        XCTAssertThrowsError(
            try client.execute(
                request,
                .oauth(OAuthCredentialFile(accessToken: "oauth-token"))
            )
        ) { error in
            XCTAssertEqual(
                error as? AiChatProviderExecutionClientError,
                .invalidCredential(provider: .openai, expected: .apiKey)
            )
        }
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 0)
    }

    func testExecute_chatgptCodexWithOAuthCredential_runsCodexExecAndEmitsFinal() throws {
        let request = makeRequest(provider: .chatgptCodex, rawModelID: "gpt-5-codex")
        let client = AiChatProviderExecutionClient.live(
            now: { 30001 },
            codexExecutor: { model, prompt, credential, onDelta in
                XCTAssertEqual(model, "gpt-5-codex")
                XCTAssertEqual(credential.accessToken, "codex-token")
                XCTAssertTrue(prompt.contains("Current context summary: workspace context"))
                XCTAssertTrue(prompt.contains("User:\nPing"))
                onDelta("Codex ")
                onDelta("answer")
                return "Codex answer\n"
            }
        )

        let events = try collect(client.execute(
            request,
            .oauth(OAuthCredentialFile(accessToken: "codex-token"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Codex "),
            .delta(context: request.context, text: "answer"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Codex answer"),
                completedAtMs: 30001
            ))
        ])
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 0)
    }

    func testExecute_openAIStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient(now: 9999) { outboundRequest in
            try assertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: openAIStreamingBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Hel"),
            .delta(context: request.context, text: "lo"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                completedAtMs: 9999
            ))
        ])
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 1)
    }

    func testExecute_openAIFinalOnlyJSON_emitsStartedFinal() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient(now: 10001) { outboundRequest in
            try assertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: openAIFinalOnlyBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                completedAtMs: 10001
            ))
        ])
    }

    func testExecute_openAI401_emitsAuthenticationFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 401,
                contentType: "application/json",
                body: #"{"error":{"message":"invalid api key"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication)
        ])
    }

    func testExecute_openAIModelError_emitsModelUnavailableFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 404,
                contentType: "application/json",
                body: #"{"error":{"message":"The model does not exist"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable)
        ])
    }

    func testExecute_openAITimeout_emitsNetworkFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            throw URLError(.timedOut)
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .network)
        ])
    }

    func testExecute_anthropicStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .tokenBudget(min: 1024, max: 4096, defaultValue: 2048)
        )
        let client = makeLiveClient(now: 20001) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .enabled(1024)
            )
            return makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamingBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Hi"),
            .delta(context: request.context, text: " there"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
                completedAtMs: 20001
            ))
        ])
    }

    func testExecute_anthropicStreamingSSEWithMessageDelta_emitsFinalInsteadOfFailure() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .effort(.low),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low)
        )
        let client = makeLiveClient(now: 200011) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low")
            )
            return makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamingBodyWithThinkingAndMessageDelta()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Final"),
            .delta(context: request.context, text: " answer"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Final answer"),
                completedAtMs: 200011
            ))
        ])
    }

    func testExecute_anthropicFinalOnlyJSON_emitsStartedFinal() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .effort(values: [.low, .high], defaultValue: nil)
        )
        let client = makeLiveClient(now: 20002) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .disabled
            )
            return makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
                completedAtMs: 20002
            ))
        ])
    }

    func testExecute_anthropicAdaptiveThinking_usesAdaptivePayloadWithoutBudgetTokens() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low)
        )
        let client = makeLiveClient { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low")
            )
            return makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events.first, .started(context: request.context))
        XCTAssertEqual(events.last, .final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
            completedAtMs: 5000
        )))
    }

    func testExecute_anthropicUnsupportedDisabledThinking_omitsThinkingPayload() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low)
        )
        let client = makeLiveClient { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .omitted
            )
            return makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody()
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .started(context: request.context))
    }

    func testExecute_anthropic401_emitsAuthenticationFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 401,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication)
        ])
    }

    func testExecute_anthropicModelError_emitsModelUnavailableFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 404,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"not_found_error","message":"model not found"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable)
        ])
    }

    func testExecute_anthropic402BillingError_emitsQuotaExceededFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 402,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"billing_error","message":"credit balance is too low"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded)
        ])
    }

    func testExecute_anthropic429QuotaMessage_emitsQuotaExceededFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 429,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"rate_limit_error","message":"quota exceeded"}}"#
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded)
        ])
    }

    func testExecute_anthropicStreamErrorEvent_emitsSpecificFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamErrorBody(type: "invalid_request_error")
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest)
        ])
    }

    func testExecute_anthropicMalformedStream_emitsInvalidRequestFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                url: "https://api.anthropic.com/v1/messages",
                statusCode: 200,
                contentType: "text/event-stream",
                body: "event: content_block_delta\ndata: {not-json}\n\n"
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest)
        ])
    }

    func testLowerRequest_detectsProviderMismatchBeforeExecution() {
        let request = makeRequest(
            provider: .openai,
            rawModelID: "claude-sonnet",
            modelProvider: .anthropic
        )

        XCTAssertThrowsError(try AiChatProviderRequestPayload.lower(request)) { error in
            XCTAssertEqual(
                error as? AiChatProviderRequestLoweringError,
                .modelProviderMismatch(requestProvider: .openai, modelProvider: .anthropic)
            )
        }
    }
}

private extension AiChatProviderExecutionClientTests {
    func makeLiveClient(
        now: Int64 = 5000,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AiChatProviderExecutionClient {
        OpenAIExecutionURLProtocol.reset()
        OpenAIExecutionURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIExecutionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return .live(session: session, now: { now })
    }

    func makeLiveClient() -> AiChatProviderExecutionClient {
        makeLiveClient { _ in
            throw URLError(.unsupportedURL)
        }
    }

    func makeRequest(
        provider: AiProvider,
        rawModelID: String,
        modelProvider: AiProvider? = nil
    ) -> AiChatRequest {
        AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000010")),
                runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000011")),
                provider: provider,
                model: AiModelHandle(provider: modelProvider ?? provider, rawValue: rawModelID),
                selectedThinking: AiThinkingSelection.none,
                sessionStatus: .idle,
                currentContext: .init(summary: "workspace context"),
                promptSummary: nil,
                submittedAtMs: 1
            ),
            messages: [AiChatMessage(role: .user, content: "Ping")]
        )
    }

    func makePreparedRequestFixture() -> AiChatRequest {
        let selectedModel = AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "selected-model-id"),
            provider: .openai,
            rawModelID: "selected-model-id",
            displayName: "Pretty Name",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
            unavailableReason: nil
        )

        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000001")),
                runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000002")),
                provider: .openai,
                model: AiModelHandle(provider: .openai, rawValue: "gpt-5.5"),
                selectedModel: selectedModel,
                selectedThinking: .effort(.high),
                sessionStatus: .idle,
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "workspace context",
                    // swiftlint:disable:next line_length
                    references: [AiChatContextReference(kind: .file, identifier: "/tmp/workspace/File.swift", title: "File.swift")],
                    // swiftlint:disable:next line_length
                    items: [AiChatContextItem(kind: .file, identifier: "item-1", title: "Notes.md", subtitle: "/tmp/workspace/Notes.md")],
                    attachments: [AiChatContextAttachment(identifier: "attachment-1", title: "Screenshot")]
                ),
                promptSummary: "summarized prompt",
                submittedAtMs: 1234
            ),
            messages: [
                AiChatMessage(role: .system, content: "System rule"),
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Previous answer")
            ]
        )
    }

    func makeAnthropicPreparedRequestFixture(
        selectedThinking: AiThinkingSelection? = .effort(.high),
        capability: AiModelThinkingCapability = .adaptive(effortValues: [.low, .high], defaultValue: .low)
    ) -> AiChatRequest {
        let selectedModel = AiProviderModel(
            id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-6"),
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            providerDisplayName: "Anthropic",
            thinkingCapability: capability,
            unavailableReason: nil
        )

        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000101")),
                runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000102")),
                provider: .anthropic,
                model: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-6"),
                selectedModel: selectedModel,
                selectedThinking: selectedThinking,
                sessionStatus: .idle,
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "workspace context",
                    // swiftlint:disable:next line_length
                    references: [AiChatContextReference(kind: .file, identifier: "/tmp/workspace/File.swift", title: "File.swift")]
                ),
                promptSummary: "anthropic prompt summary",
                submittedAtMs: 2345
            ),
            messages: [
                AiChatMessage(role: .system, content: "Answer briefly"),
                AiChatMessage(role: .user, content: "Say hi"),
                AiChatMessage(role: .assistant, content: "Previous reply")
            ]
        )
    }
}

private struct CapturedOpenAIRequestBody: Decodable {
    let model: String
    let input: [CapturedOpenAIInputItem]
    let reasoning: CapturedOpenAIReasoning?
    let stream: Bool
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

private struct CapturedAnthropicRequestBody: Decodable {
    let model: String
    let maxTokens: Int
    let messages: [CapturedAnthropicMessage]
    let system: String?
    let thinking: CapturedAnthropicThinking?
    let outputConfig: CapturedAnthropicOutputConfig?
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

private struct CapturedAnthropicOutputConfig: Decodable {
    let effort: String?
}

private struct CapturedAnthropicMessage: Decodable {
    let role: String
    let content: String
}

private struct CapturedAnthropicThinking: Decodable {
    let type: String
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

private enum ExpectedAnthropicThinking: Equatable {
    case disabled
    case enabled(Int)
    case adaptive(String)
    case omitted
}

private final class OpenAIExecutionURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static var count = 0
    private nonisolated(unsafe) static var currentHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { currentHandler }
        set { currentHandler = newValue }
    }

    static var requestCount: Int { count }

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

private func assertOpenAIRequest(_ request: URLRequest, expectedModel: String) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(requestBodyData(for: request))
    let decoded = try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.reasoning?.effort, "high")
    XCTAssertEqual(decoded.input.map(\.role), ["developer", "developer", "user", "assistant"])
    XCTAssertEqual(decoded.input.first?.content.contains("Current context summary: workspace context"), true)
    XCTAssertEqual(decoded.input.first?.content.contains("Use this context when answering the user."), true)
    XCTAssertEqual(decoded.input[1].content, "System rule")
    XCTAssertEqual(decoded.input[2].content, "Hello")
    XCTAssertEqual(decoded.input[3].content, "Previous answer")
}

private func assertAnthropicRequest(
    _ request: URLRequest,
    expectedModel: String,
    expectedThinking: ExpectedAnthropicThinking
) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(requestBodyData(for: request))
    let decoded = try JSONDecoder().decode(CapturedAnthropicRequestBody.self, from: body)
    XCTAssertEqual(decoded.model, expectedModel)
    XCTAssertEqual(decoded.maxTokens, 4096)
    XCTAssertTrue(decoded.stream)
    XCTAssertEqual(decoded.system?.contains("Current context summary: workspace context"), true)
    XCTAssertEqual(decoded.system?.contains("Answer briefly"), true)
    XCTAssertEqual(decoded.messages.map(\.role), ["user", "assistant"])
    XCTAssertEqual(decoded.messages.first?.content, "Say hi")
    XCTAssertEqual(decoded.messages.last?.content, "Previous reply")

    switch expectedThinking {
    case .disabled:
        XCTAssertEqual(decoded.thinking?.type, "disabled")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertNil(decoded.outputConfig)
    case let .enabled(budget):
        XCTAssertEqual(decoded.thinking?.type, "enabled")
        XCTAssertEqual(decoded.thinking?.budgetTokens, budget)
        XCTAssertNil(decoded.outputConfig)
    case let .adaptive(effort):
        XCTAssertEqual(decoded.thinking?.type, "adaptive")
        XCTAssertNil(decoded.thinking?.budgetTokens)
        XCTAssertEqual(decoded.outputConfig?.effort, effort)
    case .omitted:
        XCTAssertNil(decoded.thinking)
        XCTAssertNil(decoded.outputConfig)
    }
}

private func requestBodyData(for request: URLRequest) throws -> Data? {
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

private func openAIStreamingBody() -> String {
    """
    event: response.created
    data: {"type":"response.created"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"Hel"}

    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"lo"}

    event: response.completed
    data: {"type":"response.completed","response":{"output_text":"Hello"}}

    data: [DONE]

    """
}

private func openAIFinalOnlyBody() -> String {
    #"{"output":[{"content":[{"type":"output_text","text":"Hello"}]}]}"#
}

private func anthropicStreamingBody() -> String {
    """
    event: message_start
    data: {"type":"message_start","message":{"content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

private func anthropicStreamingBodyWithThinkingAndMessageDelta() -> String {
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

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":861}}

    event: message_stop
    data: {"type":"message_stop"}

    """
}

private func anthropicStreamErrorBody(type: String) -> String {
    """
    event: error
    data: {"type":"error","error":{"type":"\(type)","message":"anthropic stream failed"}}

    """
}

private func anthropicFinalOnlyBody() -> String {
    #"{"content":[{"type":"text","text":"Hi there"}],"stop_reason":"end_turn"}"#
}

private func makeHTTPResponse(
    statusCode: Int,
    contentType: String,
    body: String,
    url: String = "https://api.openai.com/v1/responses"
) -> (HTTPURLResponse, Data) {
    let resolvedURL = URL(string: url) ?? URL(fileURLWithPath: "/invalid-url")
    let response = HTTPURLResponse(
        url: resolvedURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": contentType]
    ) ?? HTTPURLResponse()
    return (response, Data(body.utf8))
}

private func makeUUID(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue) ?? UUID()
}

private func collect(
    _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>
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

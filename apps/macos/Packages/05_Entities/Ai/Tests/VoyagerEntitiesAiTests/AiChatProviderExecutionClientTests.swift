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
                .oauth(OAuthCredentialFile(accessToken: "oauth-token")),
            ),
        ) { error in
            XCTAssertEqual(
                error as? AiChatProviderExecutionClientError,
                .invalidCredential(provider: .openai, expected: .apiKey),
            )
        }
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 0)
    }

    func testExecute_chatgptCodexWithOAuthCredential_runsCodexExecAndEmitsFinal() throws {
        let request = makeRequest(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            selectedThinking: .effort(.high),
            thinkingCapability: .effort(values: [.low, .high], defaultValue: .low),
        )
        let client = AiChatProviderExecutionClient.live(
            now: { 30001 },
            codexExecutor: { model, prompt, thinking, credential, onDelta in
                XCTAssertEqual(model, "gpt-5-codex")
                XCTAssertEqual(thinking, .effort(.high))
                XCTAssertEqual(credential.accessToken, "codex-token")
                XCTAssertTrue(prompt.contains("current_context:"))
                XCTAssertTrue(prompt.contains("summary: locked workspace context"))
                XCTAssertTrue(prompt.contains("added_attachments:"))
                XCTAssertTrue(prompt.contains("Notes.txt [resolvedText]"))
                XCTAssertTrue(prompt.contains("Attachment body from locked snapshot"))
                XCTAssertTrue(prompt.contains("User:\nPing"))
                onDelta("Codex ")
                onDelta("answer")
                return "Codex answer\n"
            },
        )

        let events = try collect(client.execute(
            request,
            .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Codex "),
            .delta(context: request.context, text: "answer"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Codex answer"),
                completedAtMs: 30001,
            )),
        ])
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 0)
    }

    func testCodexProcessStateTerminatesProcessSetAfterCancellation() throws {
        let state = CodexProcessState(cleanupURLs: [])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()

        state.cancel()
        state.set(process: process)
        process.waitUntilExit()

        XCTAssertFalse(process.isRunning)
        XCTAssertNotEqual(process.terminationStatus, 0)
    }

    func testCodexJSONLineParser_acceptsCurrentAgentMessageDeltaShapes() {
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexAgentMessageDelta(
                fromJSONLine: #"{"method":"item/agentMessage/delta","params":{"delta":"Hel"}}"#,
            ),
            "Hel",
        )
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexAgentMessageDelta(
                fromJSONLine: #"{"type":"item.delta","item":{"type":"agent_message","text":"lo"}}"#,
            ),
            "lo",
        )
        let updatedLine = #"""
        {
          "type": "item.updated",
          "item": {
            "type": "message",
            "role": "assistant",
            "content": [{ "type": "output_text", "text": " there" }]
          }
        }
        """#
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexAgentMessageDelta(fromJSONLine: updatedLine),
            "there",
        )
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexAgentMessageDelta(
                fromJSONLine: #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Done"}}"#,
            ),
            "Done",
        )
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexAgentMessageDelta(
                fromJSONLine: #"""
                {"method":"item/completed","params":{"item":{"type":"agent_message","text":"Method done"}}}
                """#,
            ),
            "Method done",
        )
    }

    func testCodexCLIErrorMapping_classifiesUsageLimitsBeforeInvalidRequest() {
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexFailureReason(
                forCLIErrorOutput: "Usage limit reached for this account",
            ),
            .quotaExceeded,
        )
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexFailureReason(
                forCLIErrorOutput: "rate limit exceeded; too many requests",
            ),
            .rateLimited,
        )
        XCTAssertEqual(
            AiChatProviderExecutionClient.codexFailureReason(
                forCLIErrorOutput: "You exceeded your current quota. Check your billing details or upgrade your plan.",
            ),
            .quotaExceeded,
        )
    }

    func testExecute_openAIStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient(now: 9999) { outboundRequest in
            try assertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: openAIStreamingBody(),
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Hel"),
            .delta(context: request.context, text: "lo"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                completedAtMs: 9999,
            )),
        ])
        XCTAssertEqual(OpenAIExecutionURLProtocol.requestCount, 1)
    }

    func testExecute_openAIStreamingFailureEvent_emitsFailureInsteadOfFinal() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { outboundRequest in
            try assertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: openAIStreamFailureBody(),
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }

    func testExecute_openAIFinalOnlyJSON_emitsStartedFinal() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient(now: 10001) { outboundRequest in
            try assertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: openAIFinalOnlyBody(),
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                completedAtMs: 10001,
            )),
        ])
    }

    func testExecute_openAI401_emitsAuthenticationFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 401,
                contentType: "application/json",
                body: #"{"error":{"message":"invalid api key"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication),
        ])
    }

    func testExecute_openAIModelError_emitsModelUnavailableFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 404,
                contentType: "application/json",
                body: #"{"error":{"message":"The model does not exist"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable),
        ])
    }

    func testExecute_openAITimeout_emitsNetworkFailure() throws {
        let request = makePreparedRequestFixture()
        let client = makeLiveClient { _ in
            throw URLError(.timedOut)
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .network),
        ])
    }

    func testExecute_anthropicStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .tokenBudget(min: 1024, max: 4096, defaultValue: 2048),
        )
        let client = makeLiveClient(now: 20001) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .enabled(1024, display: "omitted"),
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamingBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Hi"),
            .delta(context: request.context, text: " there"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
                completedAtMs: 20001,
            )),
        ])
    }

    func testExecute_anthropicStreamingSSEWithMessageDelta_emitsFinalInsteadOfFailure() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .effort(.low),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = makeLiveClient(now: 200_011) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low", display: "omitted"),
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamingBodyWithThinkingAndMessageDelta(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Final"),
            .delta(context: request.context, text: " answer"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Final answer"),
                completedAtMs: 200_011,
            )),
        ])
    }

    func testAnthropicSSEByteFrameAccumulator_emitsPayloadBeforeStreamFinish() throws {
        var accumulator = SSEByteFrameAccumulator()
        var payloads: [String] = []
        let firstFrames = """
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}
        """ + "\n\n"
        for byte in firstFrames.utf8 {
            try payloads.append(contentsOf: accumulator.consume(byte))
        }

        XCTAssertEqual(payloads.count, 1)
        var state = AnthropicStreamConsumptionState()
        let decoder = JSONDecoder()
        XCTAssertEqual(
            try AiChatProviderExecutionClient.consumeAnthropicPayload(
                XCTUnwrap(payloads.first),
                decoder: decoder,
                state: &state,
            ),
            "Hi",
        )
        XCTAssertEqual(state.response.finalText, "Hi")
    }

    func testExecute_anthropicDirectEffort_encodesOutputConfigEffort() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .effort(.high),
            capability: .effort(values: [.low, .high], defaultValue: nil),
        )
        let client = makeLiveClient(now: 20002) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .outputConfigEffort("high"),
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events.first, .started(context: request.context))
        XCTAssertEqual(events.last, .final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
            completedAtMs: 20002,
        )))
    }

    func testExecute_anthropicFinalOnlyJSON_emitsStartedFinal() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .effort(values: [.low, .high], defaultValue: nil),
            supportsThinkingNone: true,
        )
        let client = makeLiveClient(now: 20002) { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .disabled,
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
                completedAtMs: 20002,
            )),
        ])
    }

    func testExecute_anthropicAdaptiveThinking_usesAdaptivePayloadWithoutBudgetTokens() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = makeLiveClient { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low", display: "omitted"),
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events.first, .started(context: request.context))
        XCTAssertEqual(events.last, .final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi there"),
            completedAtMs: 5000,
        )))
    }

    func testExecute_anthropicUnsupportedDisabledThinking_omitsThinkingPayload() throws {
        let request = makeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = makeLiveClient { outboundRequest in
            try assertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .omitted,
            )
            return makeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: anthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .started(context: request.context))
    }

    func testExecute_anthropic401_emitsAuthenticationFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 401,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication),
        ])
    }

    func testExecute_anthropicModelError_emitsModelUnavailableFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 404,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"not_found_error","message":"model not found"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable),
        ])
    }

    func testExecute_anthropic402BillingError_emitsQuotaExceededFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 402,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"billing_error","message":"credit balance is too low"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded),
        ])
    }

    func testExecute_anthropic429QuotaMessage_emitsQuotaExceededFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 429,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"rate_limit_error","message":"quota exceeded"}}"#,
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded),
        ])
    }

    func testExecute_anthropicStreamErrorEvent_emitsSpecificFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: anthropicStreamErrorBody(type: "invalid_request_error"),
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }

    func testExecute_anthropicMalformedStream_emitsInvalidRequestFailure() throws {
        let request = makeAnthropicPreparedRequestFixture()
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: "event: content_block_delta\ndata: {not-json}\n\n",
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try collect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }

    func testLowerRequest_usesLockedRequestContextForPayload() throws {
        let request = makePreparedRequestFixture()

        let payload = try AiChatProviderRequestPayload.lower(request)

        XCTAssertEqual(payload.context.requestContext, request.context.requestContext)
        XCTAssertEqual(payload.context.currentContext.summary, "locked workspace context")
        XCTAssertEqual(payload.context.requestContext.addedAttachments.count, 4)
        XCTAssertEqual(payload.context.requestContext.addedAttachments.first?.displayTitle, "Notes.txt")
        XCTAssertEqual(payload.context.requestContext.currentContext.summary, "locked workspace context")
        XCTAssertEqual(
            payload.context.requestContext.currentContext.summary,
            request.context.requestContext.currentContext.summary,
        )
        XCTAssertEqual(request.context.currentContext.summary, "locked workspace context")
        XCTAssertEqual(
            payload.context.requestContext.currentContext.summary,
            request.context.currentContext.summary,
        )
    }

    func testLowerRequest_detectsProviderMismatchBeforeExecution() {
        let request = makeRequest(
            provider: .openai,
            rawModelID: "claude-sonnet",
            modelProvider: .anthropic,
        )

        XCTAssertThrowsError(try AiChatProviderRequestPayload.lower(request)) { error in
            XCTAssertEqual(
                error as? AiChatProviderRequestLoweringError,
                .modelProviderMismatch(requestProvider: .openai, modelProvider: .anthropic),
            )
        }
    }
}

private extension AiChatProviderExecutionClientTests {
    func makeLiveClient(
        now: Int64 = 5000,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
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
        modelProvider: AiProvider? = nil,
        selectedThinking: AiThinkingSelection? = AiThinkingSelection.none,
        thinkingCapability: AiModelThinkingCapability? = nil,
    ) -> AiChatRequest {
        let resolvedProvider = modelProvider ?? provider
        let selectedModel = thinkingCapability.map { capability in
            AiProviderModel(
                id: AiModelHandle(provider: resolvedProvider, rawValue: rawModelID),
                provider: resolvedProvider,
                rawModelID: rawModelID,
                displayName: rawModelID,
                providerDisplayName: resolvedProvider.rawValue,
                thinkingCapability: capability,
                unavailableReason: nil,
            )
        }
        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000010")),
                runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000011")),
                provider: provider,
                model: AiModelHandle(provider: resolvedProvider, rawValue: rawModelID),
                selectedModel: selectedModel,
                selectedThinking: selectedThinking,
                sessionStatus: .idle,
                currentContext: .init(summary: "workspace context"),
                requestContext: makeLockedRequestContextFixture(),
                promptSummary: nil,
                submittedAtMs: 1,
            ),
            messages: [AiChatMessage(role: .user, content: "Ping")],
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
            unavailableReason: nil,
        )

        let lockedRequestContext = makeLockedRequestContextFixture()

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
                    summary: "live workspace context",
                    attachments: [
                        AiChatContextAttachment(
                            identifier: "live-attachment",
                            title: "Should not leak live attachment",
                        ),
                    ],
                ),
                requestContext: lockedRequestContext,
                promptSummary: "summarized prompt",
                submittedAtMs: 1234,
            ),
            messages: [
                AiChatMessage(role: .system, content: "System rule"),
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Previous answer"),
            ],
        )
    }

    func makeAnthropicPreparedRequestFixture(
        selectedThinking: AiThinkingSelection? = .effort(.high),
        capability: AiModelThinkingCapability = .adaptive(effortValues: [.low, .high], defaultValue: .low),
        supportsThinkingNone: Bool = false,
    ) -> AiChatRequest {
        let selectedModel = AiProviderModel(
            id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-6"),
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            providerDisplayName: "Anthropic",
            thinkingCapability: capability,
            supportsThinkingNone: supportsThinkingNone,
            unavailableReason: nil,
        )

        let lockedRequestContext = makeLockedRequestContextFixture()

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
                    summary: "live workspace context",
                    references: [
                        AiChatContextReference(
                            kind: .file,
                            identifier: "/tmp/workspace/Live.swift",
                            title: "Live.swift",
                        ),
                    ],
                ),
                requestContext: lockedRequestContext,
                promptSummary: "anthropic prompt summary",
                submittedAtMs: 2345,
            ),
            messages: [
                AiChatMessage(role: .system, content: "Answer briefly"),
                AiChatMessage(role: .user, content: "Say hi"),
                AiChatMessage(role: .assistant, content: "Previous reply"),
            ],
        )
    }

    func makeLockedRequestContextFixture() -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: makeLockedCurrentContextFixture(),
            addedAttachments: makeLockedAttachmentSnapshotFixtures(),
        )
    }

    private func makeLockedCurrentContextFixture() -> AiChatCurrentContextSnapshot {
        AiChatCurrentContextSnapshot(
            summary: "locked workspace context",
            references: [
                AiChatContextReference(
                    kind: .file,
                    identifier: "/tmp/workspace/File.swift",
                    title: "File.swift",
                ),
            ],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: "item-1",
                    title: "Notes.md",
                    subtitle: "/tmp/workspace/Notes.md",
                    references: [
                        AiChatContextReference(
                            kind: .selection,
                            identifier: "selection-1",
                            title: "Selected lines 1-4",
                        ),
                    ],
                ),
            ],
            attachments: [
                AiChatContextAttachment(identifier: "attachment-1", title: "Screenshot"),
            ],
        )
    }

    private func makeLockedAttachmentSnapshotFixtures() -> [AiChatAttachmentSnapshot] {
        [
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "attachment-text"),
                source: .file,
                displayTitle: "Notes.txt",
                subtitle: "Locked note",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Notes.txt"),
                metadata: ["mimeType": "text/plain"],
                resolutionResult: .resolvedText(
                    text: "Attachment body from locked snapshot",
                    metadata: ["encoding": "utf-8"],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "attachment-reference"),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Workspace.voycoll"),
                metadata: ["mimeType": "application/x-voycoll"],
                resolutionResult: .resolvedReference(
                    metadata: ["resolution": "reference_only"],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "attachment-too-large"),
                source: .file,
                displayTitle: "Large.bin",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Large.bin"),
                metadata: ["mimeType": "application/octet-stream"],
                resolutionResult: .failure(
                    reason: .tooLarge,
                    metadata: ["limitBytes": "65536"],
                ),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "attachment-unsupported"),
                source: .file,
                displayTitle: "Unsupported.bin",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/workspace/Unsupported.bin"),
                metadata: ["mimeType": "application/octet-stream"],
                resolutionResult: .failure(
                    reason: .unsupportedType,
                    metadata: ["detectedType": "application/octet-stream"],
                ),
            ),
        ]
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
    let content: CapturedOpenAIContent
}

private enum CapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([CapturedOpenAIContentItem])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts(try container.decode([CapturedOpenAIContentItem].self))
    }

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [CapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
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

private struct CapturedAnthropicThinking: Decodable {
    let type: String
    let budgetTokens: Int?
    let display: String?

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
        case display
    }
}

private enum ExpectedAnthropicThinking: Equatable {
    case disabled
    case enabled(Int, display: String?)
    case outputConfigEffort(String)
    case adaptive(String, display: String?)
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
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(requestBodyData(for: request))
    let decoded = try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)
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

private func assertAnthropicRequest(
    _ request: URLRequest,
    expectedModel: String,
    expectedThinking: ExpectedAnthropicThinking,
) throws {
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
    XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

    let body = try XCTUnwrap(requestBodyData(for: request))
    let decoded = try JSONDecoder().decode(CapturedAnthropicRequestBody.self, from: body)
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

private func openAIStreamFailureBody() -> String {
    """
    event: response.output_text.delta
    data: {"type":"response.output_text.delta","delta":"partial"}

    event: response.failed
    data: {"type":"response.failed","error":{"message":"OpenAI stream failed"}}

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

private func makeUUID(_ rawValue: String) -> UUID {
    UUID(uuidString: rawValue) ?? UUID()
}

private func collect(
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

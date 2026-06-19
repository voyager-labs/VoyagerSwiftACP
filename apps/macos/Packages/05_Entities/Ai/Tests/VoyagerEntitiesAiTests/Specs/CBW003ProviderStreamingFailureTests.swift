@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

// MARK: - CBW-003-stream_contextual_chat_response

final class CBW003ProviderStreamingFailureTests: XCTestCase {
    override func tearDown() {
        ProviderExecutionURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - CBW-003-stream_contextual_chat_response

    /// CBW-003-stream_contextual_chat_response: ChatGPT Codex stream cancellation은 terminal event 없이 executor를 중단한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: Codex executor cancellation 전달과 terminal event 부재를 확인합니다.
    /// - 사전 조건: 취소 대기 가능한 Codex executor fixture를 사용합니다.
    /// - 기대 결과: started event만 남고 final/failed event는 없습니다.
    func testExecute_chatgptCodexStreamCancellation_stopsExecutorWithoutTerminalEvent() async throws {
        let request = providerExecutionMakeRequest(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            selectedThinking: .effort(.high),
            capability: .effort(values: [.low, .high], defaultValue: .low),
        )
        let executorEntered = XCTestExpectation(description: "Codex executor entered")
        let startedObserved = XCTestExpectation(description: "Consumer observed started event")
        let executorCancelled = XCTestExpectation(description: "Codex executor cancelled")
        let consumerFinished = XCTestExpectation(description: "Consumer finished")
        let client = makeCancellableCodexClient(
            executorEntered: executorEntered,
            executorCancelled: executorCancelled,
        )
        let stream = try client.execute(request, .oauth(OAuthCredentialFile(accessToken: "codex-token")))
        let consumerTask = providerExecutionConsumeUntilCancelled(
            stream,
            startedObserved: startedObserved,
            finished: consumerFinished,
        )

        XCTAssertEqual(XCTWaiter.wait(for: [executorEntered, startedObserved], timeout: 1.0), .completed)
        consumerTask.cancel()
        XCTAssertEqual(XCTWaiter.wait(for: [executorCancelled, consumerFinished], timeout: 1.0), .completed)

        let events = await consumerTask.value
        XCTAssertEqual(events, [.started(context: request.context)])
        XCTAssertFalse(events.providerExecutionContainsTerminalEvent)
    }

    /// CBW-003-stream_contextual_chat_response: registry executor cancellation은 producer를 terminal event 없이 중단한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: registry stream producer 취소와 terminal event 부재를 확인합니다.
    /// - 사전 조건: cancellable registry stream fixture를 사용합니다.
    /// - 기대 결과: started event만 남고 producer/consumer cancellation이 완료됩니다.
    func testExecute_registryExecutorCancellation_stopsProducerWithoutTerminalEvent() async throws {
        let request = providerExecutionMakeRequest(provider: .openai, rawModelID: "gpt-5.5")
        let producerEntered = XCTestExpectation(description: "Registry executor entered")
        let startedObserved = XCTestExpectation(description: "Registry consumer observed started event")
        let producerCancelled = XCTestExpectation(description: "Registry executor cancelled")
        let consumerFinished = XCTestExpectation(description: "Registry consumer finished")
        let registry = makeCancellableRegistry(
            producerEntered: producerEntered,
            producerCancelled: producerCancelled,
        )
        let client = AiChatProviderExecutionClient.live(registry: registry)
        let stream = try client.execute(request, .apiKey(APIKeyCredentialFile(secret: "sk-openai")))
        let consumerTask = providerExecutionConsumeUntilCancelled(
            stream,
            startedObserved: startedObserved,
            finished: consumerFinished,
        )

        XCTAssertEqual(XCTWaiter.wait(for: [producerEntered, startedObserved], timeout: 1.0), .completed)
        consumerTask.cancel()
        XCTAssertEqual(XCTWaiter.wait(for: [producerCancelled, consumerFinished], timeout: 1.0), .completed)

        let events = await consumerTask.value
        XCTAssertEqual(events, [.started(context: request.context)])
        XCTAssertFalse(events.providerExecutionContainsTerminalEvent)
    }

    /// CBW-003-stream_contextual_chat_response: OpenAI streaming SSE는 started, delta, final 순서로 방출된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: OpenAI SSE chunk가 execution event 순서로 변환되는지 확인합니다.
    /// - 사전 조건: OpenAI text/event-stream fixture를 사용합니다.
    /// - 기대 결과: started → delta → delta → final event가 반환됩니다.
    func testExecute_openAIStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient(now: 9999) { outboundRequest in
            try providerExecutionAssertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: providerExecutionOpenAIStreamingBody(),
            )
        }

        let events = try providerExecutionCollect(client.execute(
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
        XCTAssertEqual(ProviderExecutionURLProtocol.requestCount, 1)
    }

    /// CBW-003-stream_contextual_chat_response: OpenAI streaming error event는 final 대신 failure를 방출한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: SSE error payload가 invalidRequest failure로 변환되는지 확인합니다.
    /// - 사전 조건: OpenAI stream failure body fixture를 사용합니다.
    /// - 기대 결과: started 이후 invalidRequest failed event가 반환됩니다.
    func testExecute_openAIStreamingFailureEvent_emitsFailureInsteadOfFinal() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { outboundRequest in
            try providerExecutionAssertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: providerExecutionOpenAIStreamFailureBody(),
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: OpenAI final-only JSON은 started와 final을 방출한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: 비-streaming JSON 응답이 final event로 수집되는지 확인합니다.
    /// - 사전 조건: OpenAI application/json final response fixture를 사용합니다.
    /// - 기대 결과: started 이후 final response가 반환됩니다.
    func testExecute_openAIFinalOnlyJSON_emitsStartedFinal() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient(now: 10001) { outboundRequest in
            try providerExecutionAssertOpenAIRequest(outboundRequest, expectedModel: "selected-model-id")
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: providerExecutionOpenAIFinalOnlyBody(),
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: OpenAI 401 응답은 authentication failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: HTTP 인증 오류가 provider failure surface에 매핑되는지 확인합니다.
    /// - 사전 조건: OpenAI 401 JSON response fixture를 사용합니다.
    /// - 기대 결과: started 이후 authentication failed event가 반환됩니다.
    func testExecute_openAI401_emitsAuthenticationFailure() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 401,
                contentType: "application/json",
                body: #"{"error":{"message":"invalid api key"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: OpenAI model error는 modelUnavailable failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: 모델 미존재 응답의 failure mapping을 확인합니다.
    /// - 사전 조건: OpenAI model-not-found JSON response fixture를 사용합니다.
    /// - 기대 결과: started 이후 modelUnavailable failed event가 반환됩니다.
    func testExecute_openAIModelError_emitsModelUnavailableFailure() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 404,
                contentType: "application/json",
                body: #"{"error":{"message":"The model does not exist"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: OpenAI timeout은 network failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: URLSession timeout error mapping을 확인합니다.
    /// - 사전 조건: OpenAI client fixture가 URLError.timedOut을 throw합니다.
    /// - 기대 결과: started 이후 network failed event가 반환됩니다.
    func testExecute_openAITimeout_emitsNetworkFailure() throws {
        let request = providerExecutionMakePreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            throw URLError(.timedOut)
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .network),
        ])
    }
}

// MARK: - CBW-003-stream_contextual_chat_response

final class CBW003ProviderStreamingFailureAnthropicTests: XCTestCase {
    override func tearDown() {
        ProviderExecutionURLProtocol.reset()
        super.tearDown()
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic streaming SSE는 started, delta, final 순서로 방출된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: Anthropic SSE message events가 execution event로 변환되는지 확인합니다.
    /// - 사전 조건: Anthropic text/event-stream fixture를 사용합니다.
    /// - 기대 결과: started → delta → final event가 반환됩니다.
    func testExecute_anthropicStreamingSSE_emitsStartedDeltaFinalInOrder() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .tokenBudget(min: 1024, max: 4096, defaultValue: 2048),
        )
        let client = providerExecutionMakeLiveClient(now: 20001) { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .enabled(1024, display: "omitted"),
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: providerExecutionAnthropicStreamingBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: Anthropic message delta stream은 failure 대신 final을 방출한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: message_delta completion을 정상 종료로 처리하는지 확인합니다.
    /// - 사전 조건: message_delta가 포함된 Anthropic SSE fixture를 사용합니다.
    /// - 기대 결과: failed event 없이 final response가 반환됩니다.
    func testExecute_anthropicStreamingSSEWithMessageDelta_emitsFinalInsteadOfFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: .effort(.low),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = providerExecutionMakeLiveClient(now: 200_011) { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low", display: "omitted"),
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: providerExecutionAnthropicStreamingBodyWithThinkingAndMessageDelta(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: Anthropic direct effort는 output config effort로 인코딩된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: outbound request의 thinking/output config lowering을 확인합니다.
    /// - 사전 조건: direct effort 선택과 Anthropic streaming fixture를 사용합니다.
    /// - 기대 결과: expected effort config가 포함되고 stream이 정상 완료됩니다.
    func testExecute_anthropicDirectEffort_encodesOutputConfigEffort() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: .effort(.high),
            capability: .effort(values: [.low, .high], defaultValue: nil),
        )
        let client = providerExecutionMakeLiveClient(now: 20002) { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .outputConfigEffort("high"),
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: providerExecutionAnthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: Anthropic final-only JSON은 started와 final을 방출한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: Anthropic JSON response가 final event로 변환되는지 확인합니다.
    /// - 사전 조건: Anthropic application/json final response fixture를 사용합니다.
    /// - 기대 결과: started 이후 final response가 반환됩니다.
    func testExecute_anthropicFinalOnlyJSON_emitsStartedFinal() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .effort(values: [.low, .high], defaultValue: nil),
            supportsThinkingNone: true,
        )
        let client = providerExecutionMakeLiveClient(now: 20002) { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .disabled,
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: providerExecutionAnthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: Anthropic adaptive thinking은 budget token 없이 payload에 반영된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: adaptive thinking payload에 budget token이 없는지 확인합니다.
    /// - 사전 조건: adaptive thinking 선택과 Anthropic final response fixture를 사용합니다.
    /// - 기대 결과: adaptive config만 포함되고 budget token 값은 포함되지 않습니다.
    func testExecute_anthropicAdaptiveThinking_usesAdaptivePayloadWithoutBudgetTokens() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: .tokenBudget(1024),
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = providerExecutionMakeLiveClient { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .adaptive("low", display: "omitted"),
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: providerExecutionAnthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
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

    /// CBW-003-stream_contextual_chat_response: Anthropic 미지원 disabled thinking은 payload에서 생략된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: 지원하지 않는 thinking 선택이 provider request에 인코딩되지 않는지 확인합니다.
    /// - 사전 조건: disabled 선택과 미지원 capability fixture를 사용합니다.
    /// - 기대 결과: thinking payload 없이 final response가 정상 반환됩니다.
    func testExecute_anthropicUnsupportedDisabledThinking_omitsThinkingPayload() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture(
            selectedThinking: AiThinkingSelection.none,
            capability: .adaptive(effortValues: [.low, .high], defaultValue: .low),
        )
        let client = providerExecutionMakeLiveClient { outboundRequest in
            try providerExecutionAssertAnthropicRequest(
                outboundRequest,
                expectedModel: "claude-sonnet-4-6",
                expectedThinking: .omitted,
            )
            return providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "application/json",
                body: providerExecutionAnthropicFinalOnlyBody(),
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .started(context: request.context))
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic 401 응답은 authentication failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: Anthropic 인증 오류 mapping을 확인합니다.
    /// - 사전 조건: Anthropic 401 response fixture를 사용합니다.
    /// - 기대 결과: started 이후 authentication failed event가 반환됩니다.
    func testExecute_anthropic401_emitsAuthenticationFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 401,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic model error는 modelUnavailable failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: Anthropic model-not-found 오류 mapping을 확인합니다.
    /// - 사전 조건: Anthropic model error JSON fixture를 사용합니다.
    /// - 기대 결과: started 이후 modelUnavailable failed event가 반환됩니다.
    func testExecute_anthropicModelError_emitsModelUnavailableFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 404,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"not_found_error","message":"model not found"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic billing error는 quotaExceeded failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: 결제/크레딧 부족 응답의 quota mapping을 확인합니다.
    /// - 사전 조건: Anthropic billing error fixture를 사용합니다.
    /// - 기대 결과: started 이후 quotaExceeded failed event가 반환됩니다.
    func testExecute_anthropic402BillingError_emitsQuotaExceededFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 402,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"billing_error","message":"credit balance is too low"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic 429 quota message는 quotaExceeded failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: rate-limit 형태의 quota message가 quotaExceeded로 분류되는지 확인합니다.
    /// - 사전 조건: Anthropic 429 quota response fixture를 사용합니다.
    /// - 기대 결과: started 이후 quotaExceeded failed event가 반환됩니다.
    func testExecute_anthropic429QuotaMessage_emitsQuotaExceededFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 429,
                contentType: "application/json",
                body: #"{"type":"error","error":{"type":"rate_limit_error","message":"quota exceeded"}}"#,
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .quotaExceeded),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic stream error event는 구체적인 failure reason을 방출한다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: SSE error event 내부 사유가 provider failure로 보존되는지 확인합니다.
    /// - 사전 조건: Anthropic stream error event fixture를 사용합니다.
    /// - 기대 결과: started 이후 기대한 specific failed event가 반환됩니다.
    func testExecute_anthropicStreamErrorEvent_emitsSpecificFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: providerExecutionAnthropicStreamErrorBody(type: "invalid_request_error"),
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: Anthropic malformed stream은 invalidRequest failure로 변환된다.
    /// Provider stream, cancellation, failure event가 CBW003 응답 흐름에 맞게 보존되는지 추적합니다.
    /// - 검증 내용: 파싱 불가능한 stream payload가 안전한 invalidRequest로 수렴하는지 확인합니다.
    /// - 사전 조건: malformed Anthropic SSE fixture를 사용합니다.
    /// - 기대 결과: started 이후 invalidRequest failed event가 반환됩니다.
    func testExecute_anthropicMalformedStream_emitsInvalidRequestFailure() throws {
        let request = providerExecutionMakeAnthropicPreparedRequestFixture()
        let client = providerExecutionMakeLiveClient { _ in
            providerExecutionMakeHTTPResponse(
                statusCode: 200,
                contentType: "text/event-stream",
                body: "event: content_block_delta\ndata: {not-json}\n\n",
                url: "https://api.anthropic.com/v1/messages",
            )
        }

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .invalidRequest),
        ])
    }
}

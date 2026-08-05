@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class CBW003ProviderExecutionRoutingTests: XCTestCase {
    override func tearDown() {
        ProviderExecutionURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - CBW-003-prepare_contextual_chat_request

    /// CBW-003-prepare_contextual_chat_request: OpenAI 요청이 registry executor로 라우팅된다.
    /// OpenAI 실행 준비가 preflight 결과와 동일한 입력으로 executor에 전달되는지 추적합니다.
    /// - 검증 내용: OpenAI provider, credential, raw model ID가 registry route 입력에 보존되는지 확인합니다.
    /// - 사전 조건: OpenAI API key credential과 gpt-5.5 request fixture를 사용합니다.
    /// - 기대 결과: started event만 방출되고 executor input이 preflight 결과와 일치합니다.
    func testExecute_openAIRoutesThroughRegistryExecutor() throws {
        try assertRegistryRoute(
            provider: .openai,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
            rawModelID: "gpt-5.5",
        )
    }

    /// CBW-003-prepare_contextual_chat_request: Anthropic 요청이 registry executor로 라우팅된다.
    /// Anthropic 실행 준비가 provider별 credential과 model ID를 보존하는지 추적합니다.
    /// - 검증 내용: Anthropic provider route와 preflight input 일치를 확인합니다.
    /// - 사전 조건: Anthropic API key credential과 Claude model request fixture를 사용합니다.
    /// - 기대 결과: registry executor가 Anthropic 입력을 받고 started event를 반환합니다.
    func testExecute_anthropicRoutesThroughRegistryExecutor() throws {
        try assertRegistryRoute(
            provider: .anthropic,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
            rawModelID: "claude-sonnet-4-6",
        )
    }

    /// CBW-003-prepare_contextual_chat_request: ChatGPT Codex 요청이 registry executor와 Codex prompt 계약을 보존한다.
    /// Codex provider의 thinking 선택과 prompt lowering이 실행 준비 단계에서 고정되는지 추적합니다.
    /// - 검증 내용: Codex route, raw model ID, high-effort thinking, current_context prompt 포함 여부를 확인합니다.
    /// - 사전 조건: OAuth credential과 gpt-5-codex request fixture를 사용합니다.
    /// - 기대 결과: executor input과 Codex prompt가 preflight payload 계약과 일치합니다.
    func testExecute_chatgptCodexRoutesThroughRegistryExecutor() throws {
        try assertRegistryRoute(
            provider: .chatgptCodex,
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
            rawModelID: "gpt-5-codex",
            selectedThinking: .effort(.high),
            capability: .effort(values: [.low, .high], defaultValue: .low),
        )
    }

    /// CBW-003-prepare_contextual_chat_request: registry executor가 없으면 network 호출 전에 실패한다.
    /// 지원되지 않는 provider route가 외부 호출 없이 차단되는지 추적합니다.
    /// - 검증 내용: 빈 registry에서 OpenAI 실행이 unsupportedProvider 오류로 종료되는지 확인합니다.
    /// - 사전 조건: URLProtocol spy와 executor가 없는 registry를 사용합니다.
    /// - 기대 결과: network request와 Codex invocation 없이 unsupportedProvider 오류가 반환됩니다.
    func testProviderExecutorRegistry_missingExecutorFailsBeforeNetwork() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderExecutionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        nonisolated(unsafe) var codexInvocationCount = 0
        let client = AiChatProviderExecutionClient.live(
            session: session,
            codexExecutor: { _, _, _, _, _ in
                codexInvocationCount += 1
                return "unreachable"
            },
            registry: AiChatProviderExecutorRegistry(executors: [:]),
        )
        let request = providerExecutionMakeRequest(provider: .openai, rawModelID: "gpt-5.5")

        XCTAssertThrowsError(
            try client.execute(request, .apiKey(APIKeyCredentialFile(secret: "sk-openai"))),
        ) { error in
            XCTAssertEqual(error as? AiChatProviderExecutionClientError, .unsupportedProvider(.openai))
        }
        XCTAssertEqual(ProviderExecutionURLProtocol.requestCount, 0)
        XCTAssertEqual(codexInvocationCount, 0)
    }

    /// CBW-003-prepare_contextual_chat_request: OpenAI OAuth credential은 network 전에 인증 실패로 차단된다.
    /// provider별 credential kind 검증이 외부 호출보다 먼저 실행되는지 추적합니다.
    /// - 검증 내용: OpenAI request에 OAuth credential을 전달하면 authentication failure가 발생하는지 확인합니다.
    /// - 사전 조건: OpenAI route와 OAuth credential fixture를 사용합니다.
    /// - 기대 결과: network request 없이 authentication 오류가 반환됩니다.
    func testExecute_openAIWithOAuthCredential_failsBeforeNetwork() throws {
        let client = providerExecutionMakeLiveClient()
        let request = providerExecutionMakeRequest(provider: .openai, rawModelID: "gpt-5.5")

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
        XCTAssertEqual(ProviderExecutionURLProtocol.requestCount, 0)
    }

    /// CBW-003-prepare_contextual_chat_request: preflight credential 실패는 registry executor 호출을 막는다.
    /// preflight 실패가 downstream executor로 누수되지 않는지 추적합니다.
    /// - 검증 내용: 잘못된 credential kind에서 executor invocation count가 0으로 유지되는지 확인합니다.
    /// - 사전 조건: Anthropic request에 OAuth credential을 연결합니다.
    /// - 기대 결과: authentication 오류가 반환되고 registry executor는 호출되지 않습니다.
    func testExecute_invalidCredentialPreflightDoesNotInvokeRegistryExecutor() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderExecutionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        nonisolated(unsafe) var executorInvocationCount = 0
        let registry = AiChatProviderExecutorRegistry(executors: [
            .openai: AiChatProviderExecutor { input in
                executorInvocationCount += 1
                return AsyncThrowingStream { continuation in
                    continuation.yield(.started(context: input.preflight.executionContext))
                    continuation.finish()
                }
            },
        ])
        let client = AiChatProviderExecutionClient.live(
            session: session,
            registry: registry,
        )
        let request = providerExecutionMakeRequest(provider: .openai, rawModelID: "gpt-5.5")

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
        XCTAssertEqual(executorInvocationCount, 0)
        XCTAssertEqual(ProviderExecutionURLProtocol.requestCount, 0)
    }

    /// CBW-003-prepare_contextual_chat_request: ChatGPT Codex OAuth 실행은 최종 응답 이벤트를 방출한다.
    /// Codex executor 경로가 request context와 OAuth token을 실행 결과로 연결하는지 추적합니다.
    /// - 검증 내용: Codex executor 입력값과 final assistant message를 확인합니다.
    /// - 사전 조건: gpt-5-codex request와 OAuth access token credential을 사용합니다.
    /// - 기대 결과: started 이후 final response가 방출되고 Codex prompt가 context를 포함합니다.
    func testExecute_chatgptCodexWithOAuthCredential_runsCodexExecAndEmitsFinal() throws {
        let request = providerExecutionMakeRequest(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            selectedThinking: .effort(.high),
            capability: .effort(values: [.low, .high], defaultValue: .low),
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
                onDelta(.agentMessageDelta(itemID: "message-legacy", delta: "Codex "))
                onDelta(.agentMessageDelta(itemID: "message-legacy", delta: "answer"))
                return "Codex answer\n"
            },
        )

        let events = try providerExecutionCollect(client.execute(
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
        XCTAssertEqual(ProviderExecutionURLProtocol.requestCount, 0)
    }
}

extension CBW003ProviderExecutionRoutingTests {
    /// CBW-003-prepare_contextual_chat_request: registry executor failure event는 failure surface를 보존한다.
    /// downstream executor가 반환한 실패 사유가 provider execution event로 유지되는지 추적합니다.
    /// - 검증 내용: registry executor의 quotaExceeded failure event를 그대로 수집합니다.
    /// - 사전 조건: OpenAI request와 실패 이벤트를 방출하는 registry executor를 사용합니다.
    /// - 기대 결과: started 이후 quotaExceeded failed event가 반환됩니다.
    /// CBW-003-prepare_contextual_chat_request: Codex App Server typed notifications가 execution stream으로 라우팅된다.
    /// injectable executor seam이 reasoning/search/tool/retry/answer lifecycle을 explicit notification으로 전달하는지 검증합니다.
    /// - 검증 내용: activity ID, begin/end ordering, retry boundary evidence, text delta/final을 확인합니다.
    /// - 사전 조건: App Server notification sequence를 방출하는 Codex executor fixture를 사용합니다.
    /// - 기대 결과: status는 typed notification에서만 발생하고 retry는 다음 explicit item boundary에서 종료됩니다.
    func testExecute_chatgptCodexAppServerNotifications_emitTypedActivities() throws {
        let request = providerExecutionMakeRequest(provider: .chatgptCodex, rawModelID: "gpt-5-codex")
        let client = AiChatProviderExecutionClient.live(
            now: { 30003 },
            codexExecutor: { _, _, _, _, onEvent in
                Self.emitCodexTypedActivityEvents(onEvent)
                return "Codex answer"
            },
        )

        let events = try providerExecutionCollect(client.execute(
            request,
            .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        ))

        XCTAssertEqual(events, codexTypedActivityExpectedEvents(context: request.context))
    }

    /// CBW-003-stream_contextual_chat_response: completed agent message만 수신해도 최종 응답을 보존한다.
    /// Codex App Server가 delta 없이 completed item text만 전달하는 정상 경로를 검증합니다.
    /// - 검증 내용: `item/completed.item.text`가 최종 assistant text의 authoritative source로 사용됩니다.
    /// - 사전 조건: agentMessage completed notification과 completed turn만 수신합니다.
    /// - 기대 결과: completed text가 비어 있지 않은 최종 응답으로 반환됩니다.
    func testCodexAppServerFinalText_completedOnlyUsesAuthoritativeItemText() throws {
        let finalText = try providerExecutionCodexAppServerFinalText([
            #"""
            {"method":"item/completed","params":{
                "item":{"id":"message-1","type":"agentMessage","text":"Hello"}
            }}
            """#,
            #"{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}"#,
        ])

        XCTAssertEqual(finalText, "Hello")
    }

    /// CBW-003-stream_contextual_chat_response: completed text는 같은 item의 delta 누적을 대체한다.
    /// 부분 delta와 authoritative completed text가 함께 와도 응답이 중복되지 않는지 검증합니다.
    /// - 검증 내용: completed text가 동일 item의 accumulated delta를 교체하고 새 delta로 방출되지 않습니다.
    /// - 사전 조건: 한 agentMessage item에 delta와 completed text를 차례로 전달합니다.
    /// - 기대 결과: 최종 응답은 completed text 한 번만 포함합니다.
    func testCodexAppServerFinalText_completedTextReplacesSameItemDeltasWithoutDuplication() throws {
        let finalText = try providerExecutionCodexAppServerFinalText([
            #"{"method":"item/agentMessage/delta","params":{"itemId":"message-1","delta":"Hel"}}"#,
            #"""
            {"method":"item/completed","params":{
                "item":{"id":"message-1","type":"agentMessage","text":"Hello"}
            }}
            """#,
            #"{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}"#,
        ])

        XCTAssertEqual(finalText, "Hello")
    }

    /// CBW-003-stream_contextual_chat_response: 여러 agent message item의 최종 text 순서를 보존한다.
    /// item 완료 순서가 뒤집혀도 시작 순서 기준으로 응답을 조립하는지 검증합니다.
    /// - 검증 내용: item ID order와 item별 authoritative completed text를 독립적으로 유지합니다.
    /// - 사전 조건: 두 item을 순서대로 시작한 뒤 역순으로 completed notification을 전달합니다.
    /// - 기대 결과: 최종 응답은 item 시작 순서대로 결합됩니다.
    func testCodexAppServerFinalText_multipleAgentMessageItemsPreserveItemOrder() throws {
        let finalText = try providerExecutionCodexAppServerFinalText([
            #"{"method":"item/started","params":{"item":{"id":"message-1","type":"agentMessage"}}}"#,
            #"{"method":"item/started","params":{"item":{"id":"message-2","type":"agentMessage"}}}"#,
            #"{"method":"item/completed","params":{"item":{"id":"message-2","type":"agentMessage","text":"Second"}}}"#,
            #"{"method":"item/completed","params":{"item":{"id":"message-1","type":"agentMessage","text":"First"}}}"#,
            #"{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}"#,
        ])

        XCTAssertEqual(finalText, "FirstSecond")
    }

    /// CBW-003-stream_contextual_chat_response: duplicate completed notification은 최종 응답에 한 번만 반영한다.
    /// App Server가 동일 item completion을 재전송해도 응답이 증식하지 않는지 검증합니다.
    /// - 검증 내용: item ID별 completed text assignment가 idempotent한지 확인합니다.
    /// - 사전 조건: 같은 agentMessage completed notification을 두 번 전달합니다.
    /// - 기대 결과: 최종 응답에는 completed text가 한 번만 포함됩니다.
    func testCodexAppServerFinalText_duplicateCompletedItemIsIdempotent() throws {
        let completed = #"""
        {"method":"item/completed","params":{
            "item":{"id":"message-1","type":"agentMessage","text":"Hello"}
        }}
        """#
        let finalText = try providerExecutionCodexAppServerFinalText([
            completed,
            completed,
            #"{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}"#,
        ])

        XCTAssertEqual(finalText, "Hello")
    }

    /// CBW-003-stream_contextual_chat_response: completed text가 없는 item은 accumulated delta를 사용한다.
    /// 구버전 또는 부분 App Server payload에서도 기존 streaming 응답을 보존하는지 검증합니다.
    /// - 검증 내용: nil completed text일 때만 동일 item의 delta fallback을 선택합니다.
    /// - 사전 조건: agentMessage delta 뒤 text가 없는 completed notification을 전달합니다.
    /// - 기대 결과: 최종 응답은 누적 delta와 일치합니다.
    func testCodexAppServerFinalText_itemWithoutCompletedTextFallsBackToDeltas() throws {
        let finalText = try providerExecutionCodexAppServerFinalText([
            #"{"method":"item/agentMessage/delta","params":{"itemId":"message-1","delta":"Hel"}}"#,
            #"{"method":"item/agentMessage/delta","params":{"itemId":"message-1","delta":"lo"}}"#,
            #"{"method":"item/completed","params":{"item":{"id":"message-1","type":"agentMessage"}}}"#,
            #"{"method":"turn/completed","params":{"turn":{"id":"turn-1","status":"completed"}}}"#,
        ])

        XCTAssertEqual(finalText, "Hello")
    }

    /// CBW-003-prepare_contextual_chat_request: Codex App Server parser는 unknown을 무시하고 malformed known을 실패시킨다.
    /// protocol evolution과 손상된 known event를 구분해 forward compatibility와 classified failure를 함께 보장합니다.
    /// - 검증 내용: unknown 처리, malformed validation, agentMessage 전용 completed text parsing을 확인합니다.
    /// - 사전 조건: unknown notification, unknown item, agent/reasoning completed item, 손상된 known notification을 사용합니다.
    /// - 기대 결과: agentMessage만 text를 보존하고 unknown은 무시되며 malformed known event는 실패합니다.
    func testCodexAppServerParser_ignoresUnknownAndRejectsMalformedKnownEvents() throws {
        XCTAssertNil(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"{"method":"future/event","params":{"secret":"must-not-log"}}"#,
        ))
        XCTAssertNil(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"""
            {"method":"item/started","params":{
                "threadId":"t","turnId":"u","startedAtMs":1,
                "item":{"id":"future-1","type":"futureItem"}
            }}
            """#,
        ))
        XCTAssertEqual(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"""
            {"method":"item/completed","params":{
                "item":{"id":"message-1","type":"agentMessage","text":"Hello"}
            }}
            """#,
        ), .itemCompleted(
            id: "message-1",
            kind: .agentMessage(phase: nil),
            completedText: "Hello",
            providerEventType: "item/completed",
        ))
        XCTAssertEqual(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"""
            {"method":"item/completed","params":{
                "item":{"id":"reason-1","type":"reasoning","text":"Ignored"}
            }}
            """#,
        ), .itemCompleted(
            id: "reason-1",
            kind: .reasoning,
            completedText: nil,
            providerEventType: "item/completed",
        ))
        XCTAssertThrowsError(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"""
            {"method":"item/started","params":{
                "threadId":"t","turnId":"u","startedAtMs":1,
                "item":{"type":"reasoning"}
            }}
            """#,
        )) { error in
            XCTAssertEqual(error as? CodexAppServerParsingError, .malformedKnownEvent("item/started"))
        }
    }

    /// CBW-003-prepare_contextual_chat_request: Codex JSONL buffer는 split UTF-8 scalar를 보존한다.
    /// Pipe chunk가 한글 byte 중간에서 나뉘어도 complete notification이 유실되지 않는지 검증합니다.
    /// - 검증 내용: byte accumulator가 newline 전까지 Data를 보존하고 원문 JSON line을 복원하는지 확인합니다.
    /// - 사전 조건: agent message delta의 한글 scalar 내부를 기준으로 두 chunk로 나눕니다.
    /// - 기대 결과: 첫 chunk는 line을 만들지 않고 두 번째 chunk 뒤 정확한 한 줄을 반환합니다.
    func testCodexJSONLineBuffer_preservesSplitUTF8Scalar() throws {
        let line = #"""
        {"method":"item/agentMessage/delta","params":{
            "threadId":"t","turnId":"u","itemId":"i","delta":"한글"
        }}
        """#
        let normalizedLine = line.split(whereSeparator: \.isNewline).joined()
        let bytes = Data((normalizedLine + "\n").utf8)
        let scalarStart = try XCTUnwrap(bytes.firstRange(of: Data("한".utf8)))
        let splitIndex = scalarStart.lowerBound + 1
        let buffer = CodexJSONLineBuffer()

        XCTAssertTrue(try buffer.append(Data(bytes[..<splitIndex])).isEmpty)
        let lines = try buffer.append(Data(bytes[splitIndex...]))

        XCTAssertEqual(lines, [Data(normalizedLine.utf8)])
        XCTAssertNil(buffer.finish())
    }

    /// CBW-003-prepare_contextual_chat_request: Codex completed notification은 terminal status만 허용한다.
    /// known terminal method의 invalid/in-progress status가 무한 대기로 이어지지 않고 malformed로 분류되는지 검증합니다.
    /// - 검증 내용: `turn/completed`의 inProgress status가 malformed known error인지 확인합니다.
    /// - 사전 조건: schema에는 존재하지만 completed notification에는 부적절한 inProgress status를 사용합니다.
    /// - 기대 결과: parser가 `malformedKnownEvent("turn/completed")`를 던집니다.
    func testCodexAppServerParser_rejectsNonterminalCompletedStatus() {
        XCTAssertThrowsError(try AiChatProviderExecutionClient.codexAppServerEvent(
            fromJSONLine: #"""
            {"method":"turn/completed","params":{
                "threadId":"t","turn":{"id":"u","items":[],"status":"inProgress"}
            }}
            """#,
        )) { error in
            XCTAssertEqual(error as? CodexAppServerParsingError, .malformedKnownEvent("turn/completed"))
        }
    }

    /// CBW-003-prepare_contextual_chat_request: Codex process는 공식 App Server stdio 명령을 사용한다.
    /// transport migration이 legacy `exec --json` argument로 회귀하지 않는지 검증합니다.
    /// - 검증 내용: command argument가 app-server stdio이고 exec/json/output-last-message가 없는지 확인합니다.
    /// - 사전 조건: 설치된 Codex 0.144.5가 제공하는 app-server CLI 계약을 사용합니다.
    /// - 기대 결과: arguments는 `app-server --listen stdio://`만 포함합니다.
    func testCodexArguments_useOfficialAppServerStdioInterface() {
        let arguments = AiChatProviderExecutionClient.codexArguments()

        XCTAssertEqual(arguments, ["app-server", "--listen", "stdio://"])
        XCTAssertFalse(arguments.contains("exec"))
        XCTAssertFalse(arguments.contains("--json"))
        XCTAssertFalse(arguments.contains("--output-last-message"))
    }

    func testExecute_registryExecutorFailureEvent_preservesFailureSurface() throws {
        let request = providerExecutionMakeRequest(provider: .openai, rawModelID: "gpt-5.5")
        let registry = AiChatProviderExecutorRegistry(executors: [
            .openai: AiChatProviderExecutor { input in
                AsyncThrowingStream { continuation in
                    continuation.yield(.started(context: input.preflight.executionContext))
                    continuation.yield(.failed(context: input.preflight.executionContext, reason: .authentication))
                    continuation.finish()
                }
            },
        ])
        let client = AiChatProviderExecutionClient.live(registry: registry)

        let events = try providerExecutionCollect(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .authentication),
        ])
    }

    /// CBW-003-prepare_contextual_chat_request: request lowering은 locked request context만 payload로 사용한다.
    /// 실행 직전 확정된 context snapshot이 provider payload에 반영되는지 추적합니다.
    /// - 검증 내용: lowered payload의 context, request ID, run ID, messages를 확인합니다.
    /// - 사전 조건: locked request context fixture와 prepared request를 사용합니다.
    /// - 기대 결과: payload가 live state가 아닌 locked snapshot 값을 포함합니다.
    func testLowerRequest_usesLockedRequestContextForPayload() throws {
        let request = providerExecutionMakePreparedRequestFixture()

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

    /// CBW-003-prepare_contextual_chat_request: selected model provider 불일치는 실행 전에 탐지된다.
    /// provider와 model provider가 어긋난 request가 payload lowering을 통과하지 않는지 추적합니다.
    /// - 검증 내용: provider mismatch가 invalidRequest 오류로 변환되는지 확인합니다.
    /// - 사전 조건: request provider와 selected model provider를 다르게 구성합니다.
    /// - 기대 결과: network/executor 실행 없이 invalidRequest failure가 반환됩니다.
    func testLowerRequest_detectsProviderMismatchBeforeExecution() {
        let request = providerExecutionMakeRequest(
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

    /// CBW-003-prepare_contextual_chat_request: credential이 없으면 preflight에서 authentication 실패가 발생한다.
    /// credential 부재가 provider 실행 전에 차단되는지 추적합니다.
    /// - 검증 내용: nil credential prepare 결과가 authentication failure인지 확인합니다.
    /// - 사전 조건: OpenAI prepared request와 nil credential을 사용합니다.
    /// - 기대 결과: preflight가 authentication 오류를 반환합니다.
    func testPrepare_nilCredential_failsAuthenticationBeforeNetwork() {
        let request = providerExecutionMakeRequest(
            provider: .openai,
            capability: .effort(values: [.high], defaultValue: nil),
        )

        XCTAssertThrowsError(try AiChatProviderPreflight.prepare(request, credential: nil)) { error in
            XCTAssertEqual(error as? AiChatProviderPreflightError, .missingCredential(.openai))
        }
    }

    /// CBW-003-prepare_contextual_chat_request: OpenAI에 잘못된 credential kind를 전달하면 authentication 실패가 발생한다.
    /// provider별 credential compatibility 검증을 추적합니다.
    /// - 검증 내용: OAuth credential을 OpenAI preflight에 넣었을 때 실패 사유를 확인합니다.
    /// - 사전 조건: OpenAI request와 OAuth credential fixture를 사용합니다.
    /// - 기대 결과: authentication failure가 반환됩니다.
    func testPrepare_openAIWrongCredentialKind_failsAuthentication() {
        let request = providerExecutionMakeRequest(
            provider: .openai,
            capability: .effort(values: [.high], defaultValue: nil),
        )

        XCTAssertThrowsError(
            try AiChatProviderPreflight.prepare(
                request,
                credential: .oauth(OAuthCredentialFile(accessToken: "oauth-token")),
            ),
        ) { error in
            XCTAssertEqual(
                error as? AiChatProviderPreflightError,
                .invalidCredential(provider: .openai, expected: .apiKey),
            )
        }
    }

    /// CBW-003-prepare_contextual_chat_request: preflight는 display name이 아니라 raw model ID를 사용한다.
    /// UI 표시 이름이 provider payload model ID로 누수되지 않는지 추적합니다.
    /// - 검증 내용: prepared payload의 rawModelID가 selected model raw ID와 같은지 확인합니다.
    /// - 사전 조건: display name과 raw model ID가 다른 selected model fixture를 사용합니다.
    /// - 기대 결과: payload model은 raw ID이고 display name은 전송 모델 값으로 사용되지 않습니다.
    func testPrepare_usesSelectedModelRawModelIDNotDisplayName() throws {
        let request = providerExecutionMakeRequest(
            provider: .openai,
            modelHandle: AiModelHandle(provider: .openai, rawValue: "handle-id"),
            selectedModel: AiProviderModel(
                id: AiModelHandle(provider: .openai, rawValue: "raw-model-id"),
                provider: .openai,
                rawModelID: "raw-model-id",
                displayName: "Fancy Marketing Name",
                providerDisplayName: "OpenAI",
                thinkingCapability: .effort(values: [.high], defaultValue: nil),
                unavailableReason: nil,
            ),
            capability: .effort(values: [.high], defaultValue: nil),
        )

        let result = try AiChatProviderPreflight.prepare(
            request,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )

        XCTAssertEqual(result.payload.rawModelID, "raw-model-id")
        XCTAssertNotEqual(result.payload.rawModelID, "Fancy Marketing Name")
    }

    /// CBW-003-prepare_contextual_chat_request: OpenAI thinking 선택은 capability matrix에 맞게 lowering된다.
    /// OpenAI reasoning payload가 none, effort, disabled 선택을 올바르게 반영하는지 추적합니다.
    /// - 검증 내용: capability별 thinking payload 결과를 matrix helper로 확인합니다.
    /// - 사전 조건: OpenAI model thinking capability fixture들을 사용합니다.
    /// - 기대 결과: 지원되는 선택만 payload로 내려가고 미지원 선택은 안전하게 처리됩니다.
    func testPrepare_openAIThinkingLoweringMatrix() throws {
        try providerExecutionAssertOpenAIThinkingLoweringMatrix()
    }

    /// CBW-003-prepare_contextual_chat_request: Codex thinking 선택은 Codex execution payload로 lowering된다.
    /// Codex provider의 effort/adaptive/disabled thinking 선택이 preflight에서 확정되는지 추적합니다.
    /// - 검증 내용: Codex capability 조합별 thinking payload 결과를 확인합니다.
    /// - 사전 조건: ChatGPT Codex request와 thinking capability matrix를 사용합니다.
    /// - 기대 결과: Codex payload가 지원 capability에 맞는 thinking 값을 포함합니다.
    func testPrepare_codexThinkingLoweringMatrix() throws {
        let capability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: .low)

        let unsupportedNone = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.none,
                capability: capability,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertNil(unsupportedNone.payload.thinking)
        XCTAssertEqual(unsupportedNone.warnings.count, 1)

        let supportedNone = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.none,
                capability: capability,
                supportsThinkingNone: true,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertEqual(supportedNone.payload.thinking, AiChatProviderThinkingPayload.none)
        XCTAssertTrue(supportedNone.warnings.isEmpty)

        let effort = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.effort(.high),
                capability: capability,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertEqual(effort.payload.thinking, .effort(.high))

        let tokenBudget = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: capability,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertNil(tokenBudget.payload.thinking)
        XCTAssertEqual(tokenBudget.warnings.count, 1)
    }

    /// CBW-003-prepare_contextual_chat_request: Anthropic thinking lowering은 capability kind를 존중한다.
    /// Anthropic token budget, adaptive, disabled 선택이 output config 계약으로 변환되는지 추적합니다.
    /// - 검증 내용: capability kind별 Anthropic thinking payload 결과를 확인합니다.
    /// - 사전 조건: Claude request와 Anthropic thinking capability matrix를 사용합니다.
    /// - 기대 결과: 지원되는 thinking config만 payload에 포함되고 불가능한 선택은 누락됩니다.
    func testPrepare_anthropicThinkingLoweringMatrix_respectsCapabilityKinds() throws {
        let effortCapability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: nil)
        let none = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.none,
                capability: effortCapability,
                supportsThinkingNone: true,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(none.payload.thinking, .disabled)

        let manualBudgetCapability = AiModelThinkingCapability.tokenBudget(min: 512, max: 2048, defaultValue: 1024)
        let budget = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: manualBudgetCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(budget.payload.thinking, .tokenBudget(1024))

        let adaptiveCapability = AiModelThinkingCapability.adaptive(effortValues: [.low, .high], defaultValue: .low)
        let adaptiveEffort = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.effort(.high),
                capability: adaptiveCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(adaptiveEffort.payload.thinking, .adaptive(defaultEffort: .high))
        XCTAssertEqual(adaptiveEffort.warnings.count, 1)

        let adaptiveBudget = try AiChatProviderPreflight.prepare(
            providerExecutionMakeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: adaptiveCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(adaptiveBudget.payload.thinking, .adaptive(defaultEffort: .low))
        XCTAssertEqual(adaptiveBudget.warnings.count, 1)
    }

    private static func emitCodexTypedActivityEvents(
        _ onEvent: @Sendable (CodexAppServerEvent) -> Void,
    ) {
        onEvent(.itemStarted(id: "reason-1", kind: .reasoning, providerEventType: "item/started"))
        onEvent(.reasoningDelta(itemID: "reason-1"))
        onEvent(.itemCompleted(
            id: "reason-1",
            kind: .reasoning,
            completedText: nil,
            providerEventType: "item/completed",
        ))
        onEvent(.itemStarted(id: "search-1", kind: .webSearch, providerEventType: "item/started"))
        onEvent(.itemCompleted(
            id: "search-1",
            kind: .webSearch,
            completedText: nil,
            providerEventType: "item/completed",
        ))
        onEvent(.itemStarted(id: "command-1", kind: .commandExecution, providerEventType: "item/started"))
        onEvent(.itemCompleted(
            id: "command-1",
            kind: .commandExecution,
            completedText: nil,
            providerEventType: "item/completed",
        ))
        onEvent(.itemStarted(id: "mcp-1", kind: .mcpToolCall, providerEventType: "item/started"))
        onEvent(.itemCompleted(
            id: "mcp-1",
            kind: .mcpToolCall,
            completedText: nil,
            providerEventType: "item/completed",
        ))
        onEvent(.error(turnID: "turn-1", willRetry: true, providerEventType: "error"))
        onEvent(.error(turnID: "turn-1", willRetry: true, providerEventType: "error"))
        onEvent(.itemStarted(
            id: "message-1",
            kind: .agentMessage(phase: nil),
            providerEventType: "item/started",
        ))
        onEvent(.agentMessageDelta(itemID: "message-1", delta: "Codex answer"))
        onEvent(.itemCompleted(
            id: "message-1",
            kind: .agentMessage(phase: nil),
            completedText: "Codex answer",
            providerEventType: "item/completed",
        ))
    }

    private func codexTypedActivityExpectedEvents(
        context: AiChatRequestContextSnapshot,
    ) -> [AiChatProviderExecutionEvent] {
        let retryID = "\(context.requestID.rawValue.uuidString.lowercased()):codex:retry:turn-1"
        return [
            .started(context: context),
            providerExecutionStatus(context, "reason-1", .thinking, .began, "item/started"),
            providerExecutionStatus(context, "reason-1", .thinking, .ended, "item/completed"),
            providerExecutionStatus(context, "search-1", .searching, .began, "item/started"),
            providerExecutionStatus(context, "search-1", .searching, .ended, "item/completed"),
            providerExecutionStatus(context, "command-1", .toolExecution, .began, "item/started"),
            providerExecutionStatus(context, "command-1", .toolExecution, .ended, "item/completed"),
            providerExecutionStatus(context, "mcp-1", .toolExecution, .began, "item/started"),
            providerExecutionStatus(context, "mcp-1", .toolExecution, .ended, "item/completed"),
            providerExecutionStatus(context, retryID, .retrying, .began, "error"),
            providerExecutionStatus(
                context,
                retryID,
                .retrying,
                .ended,
                "item/started",
                origin: .voyagerClient,
                boundaryEventTypes: ["error", "item/started"],
            ),
            providerExecutionStatus(context, "message-1", .answerGeneration, .began, "item/started"),
            .delta(context: context, text: "Codex answer"),
            providerExecutionStatus(context, "message-1", .answerGeneration, .ended, "item/completed"),
            .final(response: AiChatResponse(
                context: context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Codex answer"),
                completedAtMs: 30003,
            )),
        ]
    }
}

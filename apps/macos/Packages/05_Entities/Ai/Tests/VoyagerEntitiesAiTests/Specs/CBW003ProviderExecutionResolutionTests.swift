import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class CBW003ProviderExecutionResolutionTests: XCTestCase {
    // MARK: - CBW-003-prepare_contextual_chat_request

    /// CBW-003-prepare_contextual_chat_request: locked context와 active provider/model을 실행 입력으로 확정한다.
    /// request preparation 단계가 선택된 모델, 사고 설정, session history, locked context를 provider preflight 결과로 낮추는지 검증합니다.
    /// - 검증 내용: preflight payload가 raw model id, thinking, message history, locked request context를 보존합니다.
    /// - 사전 조건: OpenAI credential과 selected model/thinking이 있는 contextual request가 준비되어 있습니다.
    /// - 기대 결과: 외부 호출 전 실행 가능한 provider payload와 execution context가 확정됩니다.
    func testPrepareContextualChatRequestBuildsExecutableInput() throws {
        let request = makeCBW003Request()

        let result = try AiChatProviderPreflight.prepare(
            request,
            credential: .apiKey(APIKeyCredentialFile(secret: FixtureCredentials.openAIApiKey)),
        )

        XCTAssertEqual(result.payload.provider, .openai)
        XCTAssertEqual(result.payload.rawModelID, "gpt-4.1-mini")
        XCTAssertEqual(result.payload.thinking, .effort(.high))
        XCTAssertEqual(result.payload.messages.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(result.payload.context.sessionID, request.context.sessionID)
        XCTAssertEqual(result.payload.context.requestContext.currentContext.summary, "Locked workspace context")
        XCTAssertEqual(result.executionContext, request.context)
    }

    // MARK: - CBW-003-build_contextual_request_payload

    /// CBW-003-build_contextual_request_payload: contextual request payload를 provider contract로 정규화한다.
    /// request payload lowering이 live draft가 아니라 locked snapshot과 session turn history만 사용하는지 검증합니다.
    /// - 검증 내용: lower 결과가 active provider/model, session id, turn history, locked context parts를 보존합니다.
    /// - 사전 조건: request에는 live current context와 구분되는 locked request context가 포함되어 있습니다.
    /// - 기대 결과: provider 호출 payload에는 고정된 request snapshot과 대화 history만 들어갑니다.
    func testBuildContextualRequestPayloadUsesLockedSnapshotAndHistory() throws {
        let request = makeCBW003Request()

        let payload = try AiChatProviderRequestPayload.lower(request, thinking: .effort(.high))

        XCTAssertEqual(payload.provider, .openai)
        XCTAssertEqual(payload.rawModelID, "gpt-4.1-mini")
        XCTAssertEqual(payload.messages.map(\.content), ["System rule", "First question", "First answer", "Follow-up"])
        XCTAssertEqual(payload.context.sessionID, request.context.sessionID)
        XCTAssertEqual(payload.context.currentContext.summary, "Locked workspace context")
        XCTAssertEqual(payload.context.requestContext.parts.map(\.source), [.currentContext, .attachment, .attachment])
        XCTAssertNotEqual(payload.context.currentContext.summary, "Live draft context should not leak")
    }

    // MARK: - CBW-003-generate_contextual_chat_response

    /// CBW-003-generate_contextual_chat_response: 준비된 payload로 provider 실행을 시작한다.
    /// provider execution seam이 preflight payload를 만든 뒤 selected provider executor로 전달하는지 검증합니다.
    /// - 검증 내용: custom executor가 preflight payload와 execution context를 받고 started/final 이벤트를 반환합니다.
    /// - 사전 조건: OpenAI executor registry와 유효한 API key credential이 주입되어 있습니다.
    /// - 기대 결과: response 생성이 시작되고 최종 assistant response 이벤트가 생성됩니다.
    func testGenerateContextualChatResponseStartsProviderExecution() async throws {
        let request = makeCBW003Request()
        let client = makeCBW003Client { input in
            XCTAssertEqual(input.preflight.payload.rawModelID, "gpt-4.1-mini")
            XCTAssertEqual(input.preflight.payload.context.requestContext, request.context.requestContext)
            return [
                .started(context: input.preflight.executionContext),
                .final(response: AiChatResponse(
                    context: input.preflight.executionContext,
                    assistantMessage: AiChatMessage(role: .assistant, content: "Generated answer"),
                    completedAtMs: input.now(),
                )),
            ]
        }

        let events = try await collectCBW003Events(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: FixtureCredentials.openAIApiKey)),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Generated answer"),
                completedAtMs: 1_700_000_000_321,
            )),
        ])
    }

    // MARK: - CBW-003-stream_contextual_chat_response

    /// CBW-003-stream_contextual_chat_response: provider delta를 순서대로 response stream 이벤트로 전달한다.
    /// streaming executor가 started 이후 delta를 순서대로 내보내고 final response로 완료하는지 검증합니다.
    /// - 검증 내용: started, delta, delta, final 이벤트 순서와 final assistant message를 확인합니다.
    /// - 사전 조건: provider executor가 두 개의 delta와 하나의 final response를 생성합니다.
    /// - 기대 결과: 소비자는 delta를 누적해 최종 completed response로 전환할 수 있습니다.
    func testStreamContextualChatResponseEmitsDeltaThenFinalInOrder() async throws {
        let request = makeCBW003Request()
        let client = makeCBW003Client { input in
            [
                .started(context: input.preflight.executionContext),
                .delta(context: input.preflight.executionContext, text: "Hel"),
                .delta(context: input.preflight.executionContext, text: "lo"),
                .final(response: AiChatResponse(
                    context: input.preflight.executionContext,
                    assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                    completedAtMs: input.now(),
                )),
            ]
        }

        let events = try await collectCBW003Events(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: FixtureCredentials.openAIApiKey)),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .delta(context: request.context, text: "Hel"),
            .delta(context: request.context, text: "lo"),
            .final(response: AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(role: .assistant, content: "Hello"),
                completedAtMs: 1_700_000_000_321,
            )),
        ])
    }

    // MARK: - CBW-003-show_request_resolution_failure

    /// CBW-003-show_request_resolution_failure: execution failure reason을 분류 가능한 이벤트로 반환한다.
    /// request preparation 또는 provider execution 실패가 failed 이벤트로 연결될 수 있는 reason을 보존하는지 검증합니다.
    /// - 검증 내용: provider-side model failure가 modelUnavailable reason으로 전달됩니다.
    /// - 사전 조건: executor가 started 이후 model unavailable failure를 생성합니다.
    /// - 기대 결과: 상위 lifecycle은 실패 이유와 regenerate 진입점을 표시할 수 있습니다.
    func testShowRequestResolutionFailurePreservesClassifiedFailureReason() async throws {
        let request = makeCBW003Request()
        let client = makeCBW003Client { input in
            [
                .started(context: input.preflight.executionContext),
                .failed(context: input.preflight.executionContext, reason: .modelUnavailable),
            ]
        }

        let events = try await collectCBW003Events(client.execute(
            request,
            .apiKey(APIKeyCredentialFile(secret: FixtureCredentials.openAIApiKey)),
        ))

        XCTAssertEqual(events, [
            .started(context: request.context),
            .failed(context: request.context, reason: .modelUnavailable),
        ])
    }

    // MARK: - CBW-003-show_response_references

    /// CBW-003-show_response_references: provider citation이 없어도 snapshot provenance를 payload에 남긴다.
    /// provider prompt가 resolved, reference-only, broken context part의 최소 provenance를 포함하고 민감한 경로를 제거하는지 검증합니다.
    /// - 검증 내용: prompt에는 주요 reference label과 broken reason이 남고 raw absolute path는 노출되지 않습니다.
    /// - 사전 조건: locked context에 inline text, collection reference, failed attachment part가 포함되어 있습니다.
    /// - 기대 결과: response reference UI가 사용할 수 있는 최소 근거 정보가 안전하게 보존됩니다.
    func testShowResponseReferencesKeepsSnapshotProvenanceWithoutSensitivePaths() throws {
        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: AiChatProviderRequestPayload.lower(makeCBW003Request(), thinking: .effort(.high)),
            credential: .apiKey(FixtureCredentials.openAIApiKey),
        )
        let decoded = try JSONDecoder().decode(CBW003OpenAIRequestBody.self, from: XCTUnwrap(request.httpBody))
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("current_context:"), prompt)
        XCTAssertTrue(prompt.contains("Selected lines"), prompt)
        XCTAssertTrue(prompt.contains("Workspace.voycoll [resolvedReference]"), prompt)
        XCTAssertTrue(prompt.contains("collection_items:"), prompt)
        XCTAssertTrue(prompt.contains("Broken.txt [readFailed]"), prompt)
        XCTAssertTrue(prompt.contains("not included: readFailed"), prompt)
        RedactionTestHelper().assertNoRawSecrets(in: prompt)
        XCTAssertFalse(prompt.contains("/Users/me/secret"), prompt)
    }

    func testCodexProcessEnvironmentExcludesUnrelatedParentSecrets() {
        let environment = AiChatProviderExecutionClient.codexProcessEnvironment(
            codexHomeURL: URL(fileURLWithPath: "/tmp/voyager-codex-home"),
            parentEnvironment: [
                "HOME": "/Users/test",
                "HTTPS_PROXY": "https://proxy.example.com",
                "LANG": "en_US.UTF-8",
                "OPENAI_API_KEY": "secret",
                "PATH": "/custom/bin",
                "UNRELATED_SECRET": "secret",
            ],
        )

        XCTAssertEqual(
            Set(environment.keys),
            Set(["CODEX_HOME", "HOME", "LANG", "PATH", "SHELL", "TMPDIR"]),
        )
        XCTAssertEqual(environment["CODEX_HOME"], "/tmp/voyager-codex-home")
        XCTAssertEqual(environment["HOME"], "/tmp/voyager-codex-home")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        )
        XCTAssertEqual(environment["SHELL"], "/bin/zsh")
        XCTAssertEqual(environment["TMPDIR"], "/tmp/voyager-codex-home/session")
        XCTAssertNil(environment["HTTPS_PROXY"])
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["UNRELATED_SECRET"])
    }
}

extension CBW003ProviderExecutionResolutionTests {
    /// CBW-003-stream_contextual_chat_response: concurrent finish는 이미 추출된 item event를 앞지를 수 없다.
    /// readability callback에서 추출된 delta/completed 처리 중 termination callback이 진입하는 순서를 검증합니다.
    /// - 검증 내용: delta callback이 중단된 동안 finish가 반환하지 않고 completed item 뒤 terminal snapshot을 만듭니다.
    /// - 사전 조건: delta와 completed는 한 append에서 추출되고 turn/completed는 newline 없이 buffer에 남아 있습니다.
    /// - 기대 결과: finish는 append 처리 후 완료되며 authoritative completed text를 반환합니다.
    func testCodexAppServerDriver_concurrentFinishCannotOvertakeExtractedItemEvents() throws {
        let deltaEntered = DispatchSemaphore(value: 0)
        let releaseDelta = DispatchSemaphore(value: 0)
        let completion = DispatchSemaphore(value: 0)
        let appendGroup = DispatchGroup()
        let finishGroup = DispatchGroup()
        let recorder = ProviderExecutionResultRecorder<String>()
        let driver = providerExecutionMakeCodexAppServerDriver(
            onEvent: { event in
                guard case .agentMessageDelta = event else { return }
                deltaEntered.signal()
                releaseDelta.wait()
            },
            onComplete: { result in
                recorder.record(result)
                completion.signal()
            },
        )
        let payload = try [
            providerExecutionCodexJSONLine(method: "item/agentMessage/delta", params: [
                "itemId": "message-1",
                "delta": "Hel",
            ]),
            providerExecutionCodexJSONLine(method: "item/completed", params: [
                "item": ["id": "message-1", "type": "agentMessage", "text": "Hello"],
            ]),
            providerExecutionCodexTurnCompletedLine(),
        ].joined(separator: "\n")

        appendGroup.enter()
        DispatchQueue.global().async {
            driver.append(Data(payload.utf8))
            appendGroup.leave()
        }
        XCTAssertEqual(deltaEntered.wait(timeout: .now() + 1), .success)

        finishGroup.enter()
        DispatchQueue.global().async {
            driver.finish()
            finishGroup.leave()
        }
        let finishBeforeRelease = finishGroup.wait(timeout: .now() + 0.05)
        releaseDelta.signal()

        XCTAssertEqual(finishBeforeRelease, .timedOut)
        XCTAssertEqual(appendGroup.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(finishGroup.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(completion.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(try XCTUnwrap(recorder.snapshot()).get(), "Hello")
    }

    /// CBW-003-stream_contextual_chat_response: unique empty agent item 수는 protocol limit을 넘을 수 없다.
    /// text가 없는 item도 ID/order storage를 소비하므로 item count 제한에 포함되는지 검증합니다.
    /// - 검증 내용: 129번째 unique agentMessage item이 terminal parsing failure를 만듭니다.
    /// - 사전 조건: 서로 다른 ID의 empty item/started notification 129개를 전달합니다.
    /// - 기대 결과: driver는 성공 final 대신 classified protocol failure로 종료합니다.
    func testCodexAppServerLimits_rejectUniqueEmptyItemOverflow() throws {
        let itemLines = try (0 ... CodexAppServerProtocolLimits.maximumAgentMessageItemCount).map { index in
            try providerExecutionCodexJSONLine(method: "item/started", params: [
                "item": ["id": "message-\(index)", "type": "agentMessage"],
            ])
        }

        XCTAssertThrowsError(try providerExecutionCodexAppServerFinalText(itemLines +
                [providerExecutionCodexTurnCompletedLine()]))
        { error in
            XCTAssertEqual(
                error as? CodexAppServerParsingError,
                .resourceLimitExceeded(.agentMessageItemCount),
            )
        }
    }

    /// CBW-003-stream_contextual_chat_response: stored agent text는 UTF-8 byte budget을 넘을 수 없다.
    /// 다중 byte text가 character count가 아니라 UTF-8 storage 기준으로 제한되는지 검증합니다.
    /// - 검증 내용: 128 KiB를 초과하는 단일 delta가 terminal parsing failure를 만듭니다.
    /// - 사전 조건: 한글 scalar로 기존 total attachment text budget보다 큰 delta를 구성합니다.
    /// - 기대 결과: driver는 oversized text를 저장하지 않고 classified protocol failure로 종료합니다.
    func testCodexAppServerLimits_rejectStoredTextUTF8ByteOverflow() throws {
        let maximumBytes = CodexAppServerProtocolLimits.maximumStoredTextUTF8Bytes
        let oversizedText = String(repeating: "한", count: maximumBytes / 3 + 1)
        let lines = try [
            providerExecutionCodexJSONLine(method: "item/agentMessage/delta", params: [
                "itemId": "message-1",
                "delta": oversizedText,
            ]),
            providerExecutionCodexTurnCompletedLine(),
        ]

        XCTAssertGreaterThan(oversizedText.utf8.count, maximumBytes)
        XCTAssertThrowsError(try providerExecutionCodexAppServerFinalText(lines)) { error in
            XCTAssertEqual(
                error as? CodexAppServerParsingError,
                .resourceLimitExceeded(.storedTextUTF8Bytes),
            )
        }
    }

    /// CBW-003-stream_contextual_chat_response: oversized agent item ID는 accumulator에 저장하지 않는다.
    /// provider-controlled ID가 order/map storage를 무제한 점유하지 못하도록 UTF-8 길이를 검증합니다.
    /// - 검증 내용: 1,025-byte item ID가 terminal parsing failure를 만듭니다.
    /// - 사전 조건: ASCII 1,025자로 구성한 agentMessage item/started notification을 전달합니다.
    /// - 기대 결과: driver는 item을 등록하지 않고 classified protocol failure로 종료합니다.
    func testCodexAppServerLimits_rejectOversizedItemID() throws {
        let oversizedID = String(
            repeating: "i",
            count: CodexAppServerProtocolLimits.maximumItemIDUTF8Bytes + 1,
        )
        let lines = try [
            providerExecutionCodexJSONLine(method: "item/started", params: [
                "item": ["id": oversizedID, "type": "agentMessage"],
            ]),
            providerExecutionCodexTurnCompletedLine(),
        ]

        XCTAssertEqual(
            oversizedID.utf8.count,
            CodexAppServerProtocolLimits.maximumItemIDUTF8Bytes + 1,
        )
        XCTAssertThrowsError(try providerExecutionCodexAppServerFinalText(lines)) { error in
            XCTAssertEqual(
                error as? CodexAppServerParsingError,
                .resourceLimitExceeded(.itemIDUTF8Bytes),
            )
        }
    }

    /// CBW-003-stream_contextual_chat_response: completed text 교체는 same-item delta storage를 즉시 해제한다.
    /// authoritative completion 이후 남은 total budget을 다른 item delta가 사용할 수 있는지 검증합니다.
    /// - 검증 내용: full-budget delta를 짧은 completion으로 교체한 뒤 두 번째 item이 남은 budget을 사용합니다.
    /// - 사전 조건: 첫 item delta는 128 KiB이고 completion은 1 byte, 두 번째 delta는 나머지 budget입니다.
    /// - 기대 결과: storage 합계가 budget 이내로 유지되고 final은 두 authoritative item 순서로 반환됩니다.
    func testCodexAppServerStorage_completedTextDiscardsReplacedDeltaBytes() throws {
        let maximumBytes = CodexAppServerProtocolLimits.maximumStoredTextUTF8Bytes
        let firstDelta = String(repeating: "x", count: maximumBytes)
        let secondDelta = String(repeating: "y", count: maximumBytes - 1)
        let finalText = try providerExecutionCodexAppServerFinalText([
            providerExecutionCodexJSONLine(method: "item/agentMessage/delta", params: [
                "itemId": "message-1",
                "delta": firstDelta,
            ]),
            providerExecutionCodexJSONLine(method: "item/completed", params: [
                "item": ["id": "message-1", "type": "agentMessage", "text": "A"],
            ]),
            providerExecutionCodexJSONLine(method: "item/agentMessage/delta", params: [
                "itemId": "message-2",
                "delta": secondDelta,
            ]),
            providerExecutionCodexTurnCompletedLine(),
        ])

        XCTAssertEqual(finalText.utf8.count, maximumBytes)
        XCTAssertTrue(finalText.hasPrefix("A"))
        XCTAssertTrue(finalText.hasSuffix("y"))
    }

    /// CBW-003-stream_contextual_chat_response: 최대 stored-text payload는 JSON escaping 후에도 허용된다.
    /// 유효한 128 KiB delta가 raw-line envelope 제한에 선행 차단되지 않는지 검증합니다.
    func testCodexAppServerLimits_acceptMaximumStoredTextAfterJSONEscaping() throws {
        let maximumStoredBytes = CodexAppServerProtocolLimits.maximumStoredTextUTF8Bytes
        let escapedText = String(repeating: "\"", count: maximumStoredBytes)
        let deltaLine = try providerExecutionCodexJSONLine(method: "item/agentMessage/delta", params: [
            "itemId": "message-1",
            "delta": escapedText,
        ])

        XCTAssertGreaterThan(deltaLine.utf8.count, maximumStoredBytes * 2)
        XCTAssertLessThanOrEqual(
            deltaLine.utf8.count,
            CodexAppServerProtocolLimits.maximumRawJSONLineBytes,
        )
        XCTAssertEqual(
            try providerExecutionCodexAppServerFinalText([
                deltaLine,
                providerExecutionCodexTurnCompletedLine(),
            ]),
            escapedText,
        )
    }

    /// CBW-003-stream_contextual_chat_response: newline 없는 raw JSON line은 byte cap을 넘을 수 없다.
    /// JSON parsing 전 stdout buffer가 provider-controlled payload로 무제한 증가하지 않는지 검증합니다.
    func testCodexAppServerLimits_rejectOversizedRawJSONLine() throws {
        let completion = DispatchSemaphore(value: 0)
        let recorder = ProviderExecutionResultRecorder<String>()
        let driver = providerExecutionMakeCodexAppServerDriver(onComplete: { result in
            recorder.record(result)
            completion.signal()
        })
        let oversizedLine = Data(
            repeating: 0x78,
            count: CodexAppServerProtocolLimits.maximumRawJSONLineBytes + 1,
        )

        driver.append(oversizedLine)

        XCTAssertEqual(completion.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try XCTUnwrap(recorder.snapshot()).get()) { error in
            XCTAssertEqual(
                error as? CodexAppServerParsingError,
                .resourceLimitExceeded(.rawJSONLineBytes),
            )
        }
    }

    /// CBW-003-stream_contextual_chat_response: retained stderr는 byte cap 초과 시 protocol을 종료한다.
    /// subprocess stderr가 종료 전까지 무제한 누적되지 않고 분류된 resource failure를 만드는지 검증합니다.
    func testCodexAppServerLimits_rejectRetainedStandardErrorOverflow() throws {
        let completion = DispatchSemaphore(value: 0)
        let recorder = ProviderExecutionResultRecorder<String>()
        let driver = providerExecutionMakeCodexAppServerDriver(onComplete: { result in
            recorder.record(result)
            completion.signal()
        })
        let accumulator = CodexPipeDataAccumulator(
            maximumBytes: CodexAppServerProtocolLimits.maximumRetainedStandardErrorBytes,
            onLimitExceeded: {
                driver.fail(.resourceLimitExceeded(.retainedStandardErrorBytes))
            },
        )
        accumulator.append(Data(
            repeating: 0x65,
            count: CodexAppServerProtocolLimits.maximumRetainedStandardErrorBytes + 1,
        ))

        XCTAssertEqual(completion.wait(timeout: .now() + 1), .success)
        XCTAssertThrowsError(try XCTUnwrap(recorder.snapshot()).get()) { error in
            XCTAssertEqual(
                error as? CodexAppServerParsingError,
                .resourceLimitExceeded(.retainedStandardErrorBytes),
            )
        }
        XCTAssertTrue(accumulator.stringValue().isEmpty)
    }

    /// CBW-003-prepare_contextual_chat_request: Codex 읽기 권한은 선택된 workspace 실제 경로로 제한된다.
    /// 같은 workspace의 비선택 파일과 외부·reference-only 경로가 permission profile에 포함되지 않는지 검증합니다.
    func testCodexReadablePaths_onlyIncludesSelectedInScopeRealPaths() {
        let workingDirectory = URL(fileURLWithPath: "/tmp/project")
        let selectedPath = "/tmp/project/Selected.swift"
        let requestContext = AiChatLockedRequestContextSnapshot(parts: [
            AiChatLockedContextPartSnapshot(
                source: .attachment,
                resolution: .providerNativeFile(
                    kind: .codexPathScope,
                    mimeType: "text/plain",
                    metadata: ["path": selectedPath],
                ),
                fileKind: .file,
                canonicalPath: selectedPath,
                displayPath: selectedPath,
            ),
            AiChatLockedContextPartSnapshot(
                source: .attachment,
                resolution: .providerNativeFile(
                    kind: .codexPathScope,
                    mimeType: "text/plain",
                    metadata: ["path": "/tmp/outside/Secret.swift"],
                ),
                fileKind: .file,
                canonicalPath: "/tmp/outside/Secret.swift",
                displayPath: "/tmp/outside/Secret.swift",
            ),
            AiChatLockedContextPartSnapshot(
                source: .attachment,
                resolution: .referenceOnly(metadata: ["path": "/tmp/project/Reference.swift"]),
                fileKind: .file,
                canonicalPath: "/tmp/project/Reference.swift",
                displayPath: "/tmp/project/Reference.swift",
            ),
        ])
        let payload = makeCodexPayload(requestContext: requestContext)

        let readablePaths = AiChatProviderExecutionClient.codexReadablePaths(
            payload: payload,
            workingDirectory: workingDirectory,
        )

        XCTAssertEqual(readablePaths.map(\.path), [selectedPath])
    }

    /// CBW-003-prepare_contextual_chat_request: Codex source scope는 잠긴 요청의 folder context에서 결정된다.
    /// 프로세스 환경 없이도 선택 경로만 읽기 허용되고 scope 밖 경로는 제외되는지 검증합니다.
    func testCodexRequestScope_usesLockedFolderContextForSelectedPaths() {
        let sourceScopeRoot = "/tmp/project"
        let selectedPath = "/tmp/project/Selected.swift"
        let outsidePath = "/tmp/outside/Secret.swift"
        let requestContext = AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(references: [
                AiChatContextReference(
                    kind: .reference,
                    identifier: sourceScopeRoot,
                    metadata: ["route": "folder", "path": sourceScopeRoot],
                ),
            ]),
            parts: [selectedPath, outsidePath].map { path in
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .providerNativeFile(
                        kind: .codexPathScope,
                        mimeType: "text/plain",
                        metadata: ["path": path],
                    ),
                    fileKind: .file,
                    canonicalPath: path,
                    displayPath: path,
                )
            },
        )
        let payload = makeCodexPayload(requestContext: requestContext)

        XCTAssertEqual(AiChatProviderExecutionClient.codexSourceScopeRoot(payload: payload)?.path, sourceScopeRoot)
        XCTAssertEqual(AiChatProviderExecutionClient.codexReadablePaths(payload: payload).map(\.path), [selectedPath])
        let prompt = AiChatProviderExecutionClient.makeCodexPrompt(payload: payload)
        XCTAssertTrue(prompt.contains("source_scope_root: \(sourceScopeRoot)"))
        XCTAssertTrue(prompt.contains("path: \(selectedPath)"))
        XCTAssertTrue(prompt.contains("path: \(outsidePath)"))
        XCTAssertTrue(prompt.contains("access: referenced path (Codex filesystem access)"))
        XCTAssertTrue(prompt.contains("status: out_of_scope"))
    }

    /// CBW-003-prepare_contextual_chat_request: folder context가 없으면 Codex 파일 접근은 fail-closed 한다.
    func testCodexRequestScope_withoutLockedFolderContextIsReferenceOnly() {
        let selectedPath = "/tmp/project/Selected.swift"
        let requestContext = AiChatLockedRequestContextSnapshot(parts: [
            AiChatLockedContextPartSnapshot(
                source: .attachment,
                resolution: .providerNativeFile(
                    kind: .codexPathScope,
                    mimeType: "text/plain",
                    metadata: ["path": selectedPath],
                ),
                fileKind: .file,
                canonicalPath: selectedPath,
                displayPath: selectedPath,
            ),
        ])
        let payload = makeCodexPayload(requestContext: requestContext)

        XCTAssertNil(AiChatProviderExecutionClient.codexSourceScopeRoot(payload: payload))
        XCTAssertTrue(AiChatProviderExecutionClient.codexReadablePaths(payload: payload).isEmpty)
        XCTAssertTrue(AiChatProviderExecutionClient.makeCodexPrompt(payload: payload)
            .contains("source_scope_root: unavailable"))
    }

    /// CBW-003-prepare_contextual_chat_request: Codex permission profile은 root deny 후 선택 경로만 재허용한다.
    /// project root 전체가 아니라 isolated session cwd와 선택 파일만 read entry가 되는지 검증합니다.
    func testCodexReferencePermissionProfile_deniesRootAndAllowsSelectedPaths() throws {
        let selectedURL = URL(fileURLWithPath: "/tmp/project/Selected.swift")
        let sessionURL = URL(fileURLWithPath: "/tmp/voyager-session")
        let configuration = try CodexReferencePermissionProfile.configuration(
            readablePaths: [selectedURL],
            sessionDirectory: sessionURL,
        )
        let lines = Set(configuration.split(separator: "\n").map(String.init))
        let selectedPath = selectedURL.resolvingSymlinksInPath().path
        let sessionPath = sessionURL.resolvingSymlinksInPath().path

        XCTAssertTrue(lines.contains("\":root\" = \"deny\""))
        XCTAssertTrue(lines.contains("\":minimal\" = \"read\""))
        XCTAssertTrue(lines.contains("\"\(selectedPath)\" = \"read\""))
        XCTAssertTrue(lines.contains("\"\(sessionPath)\" = \"read\""))
        XCTAssertFalse(lines.contains("\"/tmp/project\" = \"read\""))
    }

    /// CBW-003-prepare_contextual_chat_request: Codex session home과 cwd는 생성 직후 실경로로 확정한다.
    /// process 환경과 cwd가 symlink alias가 아닌 permission profile의 canonical path를 공유하는지 검증합니다.
    func testCodexSessionEnvironment_canonicalizesHomeAndWorkingDirectory() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("voyager-codex-environment-\(UUID().uuidString)", isDirectory: true)
        let realTemporaryDirectory = fixtureRoot.appendingPathComponent("real", isDirectory: true)
        let symlinkTemporaryDirectory = fixtureRoot.appendingPathComponent("alias", isDirectory: true)
        try fileManager.createDirectory(at: realTemporaryDirectory, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: symlinkTemporaryDirectory,
            withDestinationURL: realTemporaryDirectory,
        )
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let session = try AiChatProviderExecutionClient.makeCodexSessionEnvironment(
            credential: OAuthCredentialFile(accessToken: "codex-token"),
            readablePaths: [],
            temporaryDirectory: symlinkTemporaryDirectory,
        )
        let canonicalTemporaryPath = CodexPathCanonicalizer.path(realTemporaryDirectory)

        XCTAssertTrue(session.homeURL.path.hasPrefix(canonicalTemporaryPath + "/voyager-codex-home-"))
        XCTAssertEqual(session.homeURL, CodexPathCanonicalizer.url(session.homeURL))
        XCTAssertEqual(session.workingDirectoryURL, CodexPathCanonicalizer.url(session.workingDirectoryURL))
        XCTAssertEqual(
            session.workingDirectoryURL.path,
            session.homeURL.appendingPathComponent("session").path,
        )
        XCTAssertFalse(session.homeURL.path.contains("/alias/"))
    }

    /// CBW-003-prepare_contextual_chat_request: Codex child 환경은 host secret을 상속하지 않는다.
    /// process에는 고정된 실행 경로와 격리 home/session 경로만 전달되는지 검증합니다.
    func testCodexProcessEnvironment_usesSecurityAllowlist() {
        let homeURL = URL(fileURLWithPath: "/tmp/voyager-codex-home")
        let environment = AiChatProviderExecutionClient.codexProcessEnvironment(codexHomeURL: homeURL)

        XCTAssertEqual(Set(environment.keys), ["CODEX_HOME", "HOME", "LANG", "PATH", "SHELL", "TMPDIR"])
        XCTAssertEqual(environment["CODEX_HOME"], homeURL.path)
        XCTAssertEqual(environment["HOME"], homeURL.path)
        XCTAssertEqual(environment["TMPDIR"], homeURL.appendingPathComponent("session").path)
        XCTAssertNil(environment["VOYAGER_CODEX_WORKING_DIRECTORY"])
    }

    /// CBW-003-prepare_contextual_chat_request: App Server는 선택 permission profile 적용을 증명해야 한다.
    /// legacy 또는 profile fallback 응답이 turn 실행으로 이어지지 않고 fail-closed 되는지 검증합니다.
    func testCodexAppServerDriver_rejectsUnverifiedPermissionProfile() {
        let recorder = ProviderExecutionResultRecorder<String>()
        let driver = providerExecutionMakeCodexAppServerDriver(onComplete: recorder.record)

        let response = #"{"id":2,"result":{"thread":{"id":"thread-1"},"sandbox":{"type":"readOnly"}}}"#
        driver.append(Data((response + "\n").utf8))

        XCTAssertThrowsError(try XCTUnwrap(recorder.snapshot()).get()) { error in
            XCTAssertEqual(error as? CodexAppServerParsingError, .malformedKnownEvent("thread/start"))
        }
    }

    /// CBW-003-prepare_contextual_chat_request: symlink session 경로는 App Server 계약 전체에서 실경로로 정규화한다.
    /// permission profile, thread cwd, 응답 검증이 동일한 canonical path를 사용하는지 검증합니다.
    func testCodexAppServerDriver_canonicalizesSymlinkedSessionPath() throws {
        let fixture = try makeCBW003SymlinkSessionFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let inputPipe = Pipe()
        let recorder = ProviderExecutionResultRecorder<String>()
        let driver = CodexAppServerProtocolDriver(
            input: inputPipe.fileHandleForWriting,
            model: "gpt-5-codex",
            prompt: "Summarize the selected file",
            thinking: nil,
            workingDirectory: fixture.aliasURL,
            onEvent: { _ in },
            onComplete: recorder.record,
        )

        try driver.start()
        _ = try providerExecutionReadJSONRequests(
            from: inputPipe.fileHandleForReading,
            expectedCount: 1,
        )
        driver.append(Data("{\"id\":1,\"result\":{}}\n".utf8))
        let initializationRequests = try providerExecutionReadJSONRequests(
            from: inputPipe.fileHandleForReading,
            expectedCount: 2,
        )
        let threadStart = try XCTUnwrap(initializationRequests.first { $0["method"] as? String == "thread/start" })
        let threadStartParams = try XCTUnwrap(threadStart["params"] as? [String: Any])
        XCTAssertEqual(threadStartParams["cwd"] as? String, fixture.canonicalPath)

        try driver.append(makeCBW003VerifiedThreadStartResponse(canonicalPath: fixture.canonicalPath))

        if recorder.snapshot() == nil {
            let turnRequests = try providerExecutionReadJSONRequests(
                from: inputPipe.fileHandleForReading,
                expectedCount: 1,
            )
            XCTAssertEqual(turnRequests.first?["method"] as? String, "turn/start")
        }
        XCTAssertNil(recorder.snapshot())
    }

    /// CBW-003-prepare_contextual_chat_request: 검증된 제한 profile만 Codex turn을 시작한다.
    /// profile·sandbox·approval·cwd·runtime root가 모두 일치할 때 turn/start가 전송되는지 검증합니다.
    func testCodexAppServerDriver_acceptsVerifiedPermissionProfile() throws {
        let inputPipe = Pipe()
        let sessionPath = "/tmp/VoyagerCodexSession"
        let driver = CodexAppServerProtocolDriver(
            input: inputPipe.fileHandleForWriting,
            model: "gpt-5-codex",
            prompt: "Summarize the selected file",
            thinking: nil,
            workingDirectory: URL(fileURLWithPath: sessionPath),
            onEvent: { _ in },
            onComplete: { _ in },
        )
        let response: [String: Any] = [
            "id": 2,
            "result": [
                "thread": ["id": "thread-1"],
                "activePermissionProfile": ["id": CodexReferencePermissionProfile.identifier],
                "sandbox": ["type": "readOnly", "networkAccess": false],
                "approvalPolicy": "never",
                "cwd": sessionPath,
                "runtimeWorkspaceRoots": [sessionPath],
            ],
        ]
        var responseData = try JSONSerialization.data(withJSONObject: response)
        responseData.append(0x0A)

        driver.append(responseData)
        let requests = try providerExecutionReadJSONRequests(
            from: inputPipe.fileHandleForReading,
            expectedCount: 1,
        )

        XCTAssertEqual(requests.first?["method"] as? String, "turn/start")
    }
}

private extension CBW003ProviderExecutionResolutionTests {
    func makeCBW003Request() -> AiChatRequest {
        let selectedModel = AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: nil),
            unavailableReason: nil,
        )

        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                sessionID: AiChatSessionID(rawValue: makeCBW003UUID("00000000-0000-0000-0000-000000000100")),
                requestID: AiChatRequestID(rawValue: makeCBW003UUID("00000000-0000-0000-0000-000000000101")),
                runID: AiChatRunID(rawValue: makeCBW003UUID("00000000-0000-0000-0000-000000000102")),
                provider: .openai,
                model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
                selectedModel: selectedModel,
                selectedThinking: .effort(.high),
                sessionStatus: .active,
                currentContext: AiChatCurrentContextSnapshot(summary: "Live draft context should not leak"),
                requestContext: makeCBW003LockedContext(),
                promptSummary: "Follow-up",
                submittedAtMs: 1_700_000_000_000,
            ),
            messages: [
                AiChatMessage(role: .system, content: "System rule"),
                AiChatMessage(role: .user, content: "First question"),
                AiChatMessage(role: .assistant, content: "First answer"),
                AiChatMessage(role: .user, content: "Follow-up"),
            ],
        )
    }

    func makeCBW003Client(
        events: @escaping @Sendable (AiChatProviderExecutionInput) throws -> [AiChatProviderExecutionEvent],
    ) -> AiChatProviderExecutionClient {
        let executor = AiChatProviderExecutor { input in
            AsyncThrowingStream { continuation in
                do {
                    for event in try events(input) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return .live(
            now: { 1_700_000_000_321 },
            registry: AiChatProviderExecutorRegistry(executors: [.openai: executor]),
        )
    }

    func collectCBW003Events(
        _ stream: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>,
    ) async throws -> [AiChatProviderExecutionEvent] {
        var events: [AiChatProviderExecutionEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func makeCBW003SymlinkSessionFixture() throws -> CBW003SymlinkSessionFixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("voyager-codex-symlink-\(UUID().uuidString)", isDirectory: true)
        let realSessionURL = rootURL.appendingPathComponent("real-session", isDirectory: true)
        let aliasURL = rootURL.appendingPathComponent("session-alias", isDirectory: true)
        try fileManager.createDirectory(at: realSessionURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: aliasURL, withDestinationURL: realSessionURL)
        let resolvedPath = aliasURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        let canonicalPath = resolvedPath.hasSuffix("/")
            ? String(resolvedPath.dropLast())
            : resolvedPath
        return CBW003SymlinkSessionFixture(
            rootURL: rootURL,
            aliasURL: aliasURL,
            canonicalPath: canonicalPath,
        )
    }

    func makeCBW003VerifiedThreadStartResponse(canonicalPath: String) throws -> Data {
        let response: [String: Any] = [
            "id": 2,
            "result": [
                "thread": ["id": "thread-1"],
                "activePermissionProfile": ["id": CodexReferencePermissionProfile.identifier],
                "sandbox": ["type": "readOnly", "networkAccess": false],
                "approvalPolicy": "never",
                "cwd": canonicalPath,
                "runtimeWorkspaceRoots": [canonicalPath],
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: response)
        data.append(0x0A)
        return data
    }

    func makeCodexPayload(requestContext: AiChatLockedRequestContextSnapshot) -> AiChatProviderRequestPayload {
        AiChatProviderRequestPayload(
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            messages: [],
            context: AiChatProviderContextBundle(
                sessionID: nil,
                requestID: AiChatRequestID(rawValue: makeCBW003UUID("00000000-0000-0000-0000-000000000201")),
                runID: AiChatRunID(rawValue: makeCBW003UUID("00000000-0000-0000-0000-000000000202")),
                requestContext: requestContext,
                promptSummary: nil,
                submittedAtMs: nil,
            ),
            thinking: nil,
        )
    }

    func makeCBW003LockedContext() -> AiChatLockedRequestContextSnapshot {
        AiChatLockedRequestContextSnapshot(
            currentContext: makeCBW003CurrentContext(),
            addedAttachments: makeCBW003AttachmentSnapshots(),
            parts: makeCBW003LockedParts(),
        )
    }

    func makeCBW003CurrentContext() -> AiChatCurrentContextSnapshot {
        AiChatCurrentContextSnapshot(
            summary: "Locked workspace context",
            items: [
                AiChatContextItem(
                    kind: .selection,
                    identifier: "selection-1",
                    title: "Selected lines",
                    metadata: ["path": "Selection.swift"],
                ),
            ],
        )
    }

    func makeCBW003AttachmentSnapshots() -> [AiChatAttachmentSnapshot] {
        [
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "collection"),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                kind: .attachment,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/Users/me/secret/Workspace.voycoll"),
                resolutionResult: .resolvedReference(metadata: [
                    "collectionItemCount": "2",
                    "collectionItemPaths": "README.md\ndesign.pdf",
                    "collectionItemsIncluded": "2",
                ]),
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "broken"),
                source: .file,
                displayTitle: "Broken.txt",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/Users/me/secret/Broken.txt"),
                resolutionResult: .failure(reason: .readFailed, metadata: ["path": "/Users/me/secret/Broken.txt"]),
            ),
        ]
    }

    func makeCBW003LockedParts() -> [AiChatLockedContextPartSnapshot] {
        [
            makeCBW003InlineTextPart(),
            makeCBW003CollectionReferencePart(),
            makeCBW003BrokenReferencePart(),
        ]
    }

    func makeCBW003InlineTextPart() -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: .currentContext,
            resolution: .inlineText(text: "Selected source body", metadata: ["encoding": "utf-8"]),
            canonicalPath: "/Users/me/secret/Selection.swift",
            displayPath: "Selection.swift",
            fileKind: .file,
            displayTitle: "Selected lines",
        )
    }

    func makeCBW003CollectionReferencePart() -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .collectionPathList(
                paths: ["README.md", "design.pdf"],
                metadata: ["collectionItemsIncluded": "2"],
            ),
            canonicalPath: "/Users/me/secret/Workspace.voycoll",
            displayPath: "Workspace.voycoll",
            fileKind: .attachment,
            displayTitle: "Workspace.voycoll",
        )
    }

    func makeCBW003BrokenReferencePart() -> AiChatLockedContextPartSnapshot {
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .failure(reason: .readFailed, metadata: ["path": "/Users/me/secret/Broken.txt"]),
            canonicalPath: "/Users/me/secret/Broken.txt",
            displayPath: "Broken.txt",
            fileKind: .file,
            displayTitle: "Broken.txt",
        )
    }

    func makeCBW003UUID(_ rawValue: String) -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return uuid
    }
}

private struct CBW003SymlinkSessionFixture {
    let rootURL: URL
    let aliasURL: URL
    let canonicalPath: String
}

private struct CBW003OpenAIRequestBody: Decodable {
    let input: [CBW003OpenAIInputItem]
}

private struct CBW003OpenAIInputItem: Decodable {
    let content: CBW003OpenAIContent
}

private enum CBW003OpenAIContent: Decodable {
    case text(String)

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try .text(container.decode(String.self))
    }
}

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

        XCTAssertEqual(environment["CODEX_HOME"], "/tmp/voyager-codex-home")
        XCTAssertEqual(environment["HOME"], "/Users/test")
        XCTAssertEqual(environment["HTTPS_PROXY"], "https://proxy.example.com")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/custom/bin",
        )
        XCTAssertNil(environment["OPENAI_API_KEY"])
        XCTAssertNil(environment["UNRELATED_SECRET"])
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

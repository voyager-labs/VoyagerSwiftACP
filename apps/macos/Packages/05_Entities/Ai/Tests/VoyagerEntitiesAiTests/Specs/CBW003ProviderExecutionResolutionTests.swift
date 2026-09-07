import Darwin
import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class CBW003ProviderExecutionResolutionTests: XCTestCase {
    private func makeCodexFile(
        state: ProviderConnectionState,
        credential: StoredCredentialPayload? = nil,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: credential == nil ? .codexCLI : .oauth,
                    credential: credential,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: state),
                ),
            ],
        )
    }

    // MARK: - CBW-003-provider_managed_codex_preflight

    /// CBW-003-provider_managed_codex_preflight: Codex credential이 없어도 provider-managed readiness를 반환한다.
    /// Voyager credential payload 없이 Codex preflight가 provider-managed 인증을 표현하는지 검증합니다.
    /// - 검증 내용: nil credential이 내부 provider-managed credential result로 정규화됩니다.
    /// - 사전 조건: Codex provider와 credential payload가 없는 preflight validation을 호출합니다.
    /// - 기대 결과: OAuth/API key를 요구하지 않고 provider-managed 결과를 반환합니다.
    func testCodexPreflightWithoutStoredCredentialUsesProviderManagedAuth() throws {
        XCTAssertEqual(
            try AiChatProviderPreflight.validateCredential(for: .chatgptCodex, credential: nil),
            .providerManaged,
        )
    }

    /// CBW-003-provider_managed_codex_preflight: Codex에 전달된 Voyager credential payload를 사용하지 않는다.
    /// Codex preflight가 OAuth 또는 API key payload를 인증 입력으로 추출하지 않는지 검증합니다.
    /// - 검증 내용: credential payload 종류와 무관하게 provider-managed result가 반환됩니다.
    /// - 사전 조건: sentinel OAuth와 API key payload를 각각 Codex validation에 전달합니다.
    /// - 기대 결과: payload secret이 결과나 오류 표면에 들어가지 않고 provider-managed 결과가 반환됩니다.
    func testCodexPreflightIgnoresOAuthAndAPIKeyPayloads() throws {
        let oauthResult = try AiChatProviderPreflight.validateCredential(
            for: .chatgptCodex,
            credential: .oauth(OAuthCredentialFile(accessToken: "sentinel-oauth")),
        )
        let apiKeyResult = try AiChatProviderPreflight.validateCredential(
            for: .chatgptCodex,
            credential: .apiKey(APIKeyCredentialFile(secret: "sentinel-api-key")),
        )

        XCTAssertEqual(oauthResult, .providerManaged)
        XCTAssertEqual(apiKeyResult, .providerManaged)
    }

    /// CBW-003-provider_managed_codex_preflight: env-only API key readiness를 성공으로 합성하지 않는다.
    /// Phase 1에서 환경 변수 API key를 읽지 않는 Codex preflight 경계를 검증합니다.
    /// - 검증 내용: stored credential이 없는 Codex 경로는 provider-managed만 반환합니다.
    /// - 사전 조건: credential 입력 없이 hermetic validation을 수행합니다.
    /// - 기대 결과: 환경 변수나 임시 credential 복사 없이 provider-managed 결과가 유지됩니다.
    func testCodexPreflightDoesNotSynthesizeEnvOnlyAPIKeyReadiness() throws {
        let result = try AiChatProviderPreflight.validateCredential(for: .chatgptCodex, credential: nil)

        XCTAssertEqual(result, .providerManaged)
    }

    /// CBW-003-provider_managed_codex_preflight: OpenAI와 Anthropic credential semantics를 유지한다.
    /// Codex 변경이 다른 provider의 API key 및 OAuth validation을 바꾸지 않는지 검증합니다.
    /// - 검증 내용: 유효한 API key는 두 provider에서 apiKey로 반환되고 OAuth는 invalidCredential입니다.
    /// - 사전 조건: sentinel API key와 OAuth payload를 OpenAI/Anthropic validation에 전달합니다.
    /// - 기대 결과: 기존 provider별 credential 계약과 오류 분류가 그대로 유지됩니다.
    func testOpenAIAndAnthropicCredentialSemanticsRemainUnchanged() throws {
        XCTAssertEqual(
            try AiChatProviderPreflight.validateCredential(
                for: .openai,
                credential: .apiKey(APIKeyCredentialFile(secret: "sentinel-openai-api-key")),
            ),
            .apiKey("sentinel-openai-api-key"),
        )
        XCTAssertEqual(
            try AiChatProviderPreflight.validateCredential(
                for: .anthropic,
                credential: .apiKey(APIKeyCredentialFile(secret: "sentinel-anthropic-api-key")),
            ),
            .apiKey("sentinel-anthropic-api-key"),
        )

        XCTAssertThrowsError(try AiChatProviderPreflight.validateCredential(
            for: .openai,
            credential: .oauth(OAuthCredentialFile(accessToken: "sentinel-oauth")),
        )) { error in
            XCTAssertEqual(
                error as? AiChatProviderPreflightError,
                .invalidCredential(provider: .openai, expected: .apiKey),
            )
        }
        XCTAssertThrowsError(try AiChatProviderPreflight.validateCredential(
            for: .anthropic,
            credential: .oauth(OAuthCredentialFile(accessToken: "sentinel-oauth")),
        )) { error in
            XCTAssertEqual(
                error as? AiChatProviderPreflightError,
                .invalidCredential(provider: .anthropic, expected: .apiKey),
            )
        }
    }

    // MARK: - CBW-003-provider_managed_codex_state

    /// CBW-003-provider_managed_codex_state: legacy Codex OAuth is sanitized without losing connected state.
    /// Codex-owned authentication must not retain native OAuth bytes in the normalized connection record.
    /// - 검증 내용: OAuth payload가 nil credential과 codexCLI metadata로 정규화되고 connected snapshot은 보존됩니다.
    /// - 사전 조건: Codex connected record에 legacy OAuth access/refresh token이 저장되어 있습니다.
    /// - 기대 결과: 정규화 결과에 OAuth bytes가 없고 provider-managed connected 상태가 유지됩니다.
    func testCodexNormalizer_sanitizesLegacyOAuthAndPreservesConnectedState() {
        let file = makeCodexFile(
            state: .connected,
            credential: .oauth(OAuthCredentialFile(
                accessToken: "sentinel-access",
                refreshToken: "sentinel-refresh",
            )),
        )

        let normalized = AIConnectionsNormalizer.normalize(file)
        let record = normalized.providers[AiProvider.chatgptCodex.rawValue]

        XCTAssertEqual(record?.authMethod, .codexCLI)
        XCTAssertNil(record?.credential)
        XCTAssertEqual(record?.snapshot.lastKnownStatus, .connected)
    }

    /// CBW-003-provider_managed_codex_state: connected Codex selection does not require a stored credential.
    /// Query routing must pass provider-managed authentication to the CLI execution boundary.
    /// - 검증 내용: credentialless connected Codex가 explicit selection context로 반환되는지 확인합니다.
    /// - 사전 조건: Codex record는 codexCLI metadata와 nil credential을 가진 connected 상태입니다.
    /// - 기대 결과: selection이 성공하고 context credential은 nil입니다.
    func testCodexQuerySelection_acceptsCredentiallessConnectedRecord() {
        let file = makeCodexFile(state: .connected)

        let selection = AIProviderQuerySelection.select(provider: .chatgptCodex, from: file)

        guard case let .success(context) = selection else {
            XCTFail("Credentialless connected Codex should be selectable")
            return
        }
        XCTAssertNil(context.credential)
    }

    /// CBW-003-provider_managed_codex_state: direct OAuth persistence is rejected for Codex.
    /// Legacy OAuth API compatibility must fail closed instead of creating a native-token record.
    /// - 검증 내용: live connection client가 Codex OAuth 연결을 unsupported 결과로 거부하는지 확인합니다.
    /// - 사전 조건: temporary repository root와 sentinel OAuth payload를 사용합니다.
    /// - 기대 결과: connection failed 결과가 반환되고 OAuth persistence는 실행되지 않습니다.
    func testCodexConnectionClient_rejectsDirectOAuthPersistence() async {
        let client = AIProviderConnectionClient.liveForRepoRoot(
            repoRootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexOAuth-\(UUID().uuidString)", isDirectory: true),
        )

        let result = await client.connectOAuth(
            .chatgptCodex,
            OAuthCredentialFile(accessToken: "sentinel-oauth"),
            .connected,
        )

        XCTAssertEqual(result.state, .connectionFailed)
        XCTAssertEqual(result.reason, .providerUnsupportedInBuild)
        XCTAssertTrue(result.updatedFile.providers.isEmpty)
    }

    /// CBW-003-provider_managed_codex_state: Codex model source ignores native OAuth payloads.
    /// Model resolution must remain available from the provider-managed catalog without reading OAuth tokens.
    /// - 검증 내용: Codex model loading accepts nil or legacy OAuth input without using the payload.
    /// - 사전 조건: model client receives a sentinel OAuth payload.
    /// - 기대 결과: a provider-managed Codex model is returned without token-dependent network work.
    func testCodexModelList_usesProviderManagedCatalogWithoutOAuth() async throws {
        let client = AiProviderModelListClient.live()
        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "sentinel-oauth")),
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5-codex"])
    }

    /// CBW-003-provider_managed_codex_state: Codex status verifies CLI ownership and persists legacy sanitization.
    /// Status checks must use CLI readiness while removing legacy OAuth metadata from the local record.
    /// - 검증 내용: status verifier receives nil credential and normalized file is written back.
    /// - 사전 조건: temporary store contains a connected legacy OAuth Codex record and readiness is valid.
    /// - 기대 결과: status is ready and stored credential is nil with connected state preserved.
    func testCodexStatus_usesCLIReadinessAndPersistsSanitizedRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatus-\(UUID().uuidString)", isDirectory: true)
        let payloadURL = directory.appendingPathComponent("auth.json")
        let lockURL = directory.appendingPathComponent("auth.lock")
        let store = AIConnectionFileStore(payloadURL: payloadURL, lockURL: lockURL)
        let file = makeCodexFile(
            state: .connected,
            credential: .oauth(OAuthCredentialFile(accessToken: "sentinel-oauth")),
        )
        try await store.write(file)

        let runtimeClient = AiConnectionRuntimeClient(
            verifyProvider: { provider, credential in
                XCTAssertEqual(provider, .chatgptCodex)
                XCTAssertNil(credential)
                return .valid
            },
            resolveAdapter: { _, _ in nil },
        )
        let client = AiConnectionStatusClient.persistenceClient(
            store: store,
            runtimeClient: runtimeClient,
        )

        let status = await client.checkStatus(.chatgptCodex)
        let normalized = try await store.load()

        XCTAssertEqual(status, .ready)
        XCTAssertEqual(
            AiConnectionRuntimeClient.readinessReason(.loginProbeFailed(1)),
            .missingCredential,
        )
        XCTAssertNil(normalized.providers[AiProvider.chatgptCodex.rawValue]?.credential)
        XCTAssertEqual(
            normalized.providers[AiProvider.chatgptCodex.rawValue]?.snapshot.lastKnownStatus,
            .connected,
        )
    }

    /// CBW-003-provider_managed_codex_state: update refuses to overwrite a newer schema file.
    /// 상위 schemaVersion 연결 파일을 빈 v1 정규화 결과로 덮어 쓰지 않는지 검증합니다.
    /// - 검증 내용: schemaVersion > 1 파일에 update가 오류를 반환하고 원본 바이트를 보존하는지 확인합니다.
    /// - 사전 조건: schemaVersion 2 연결 파일이 저장소에 기록되어 있습니다.
    /// - 기대 결과: update는 unsupportedSchemaVersion 오류를 반환하고 디스크 파일이 그대로 유지됩니다.
    func testUpdate_unsupportedSchemaVersionThrowsAndPreservesFile() async throws {
        let (store, payloadURL) = try makeTemporaryStore()
        let newerSchemaFile = AIConnectionsFile(
            updatedAtMs: 7,
            schemaVersion: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .codexCLI,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(newerSchemaFile)
        let originalBytes = try Data(contentsOf: payloadURL)

        do {
            _ = try await store.update { AIConnectionsNormalizer.normalize($0) }
            XCTFail("update must refuse a newer schema file")
        } catch {
            XCTAssertEqual(error as? AIConnectionFileStoreError, .unsupportedSchemaVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: payloadURL), originalBytes)
    }

    /// CBW-003-provider_managed_codex_state: deleteCredential refuses a newer schema file.
    /// 상위 schemaVersion 파일을 재인코딩으로 훼손하지 않는지 검증합니다.
    /// - 검증 내용: schemaVersion > 1 파일에 deleteCredential이 오류를 반환하는지 확인합니다.
    /// - 사전 조건: schemaVersion 2 연결 파일이 저장소에 기록되어 있습니다.
    /// - 기대 결과: deleteCredential은 unsupportedSchemaVersion 오류를 반환하고 디스크 파일이 유지됩니다.
    func testDeleteCredential_unsupportedSchemaVersionThrowsAndPreservesFile() async throws {
        let (store, payloadURL) = try makeTemporaryStore()
        let newerSchemaFile = AIConnectionsFile(
            updatedAtMs: 7,
            schemaVersion: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .codexCLI,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(newerSchemaFile)
        let originalBytes = try Data(contentsOf: payloadURL)

        do {
            try await store.deleteCredential(for: .chatgptCodex)
            XCTFail("deleteCredential must refuse a newer schema file")
        } catch {
            XCTAssertEqual(error as? AIConnectionFileStoreError, .unsupportedSchemaVersion(2))
        }
        XCTAssertEqual(try Data(contentsOf: payloadURL), originalBytes)
    }

    /// CBW-003-provider_managed_codex_state: status check never persists a newer schema file away.
    /// 상태 조회가 상위 schemaVersion 파일을 덮어 쓰지 않는지 검증합니다.
    /// - 검증 내용: checkStatus가 미지원 schema에서 상태만 판정하고 디스크를 보존하는지 확인합니다.
    /// - 사전 조건: schemaVersion 2 연결 파일과 유효한 runtime client가 제공됩니다.
    /// - 기대 결과: status는 notConfigured이고 원본 파일 바이트가 그대로 유지됩니다.
    func testCodexStatus_unsupportedSchemaVersionDoesNotOverwriteFile() async throws {
        let (store, payloadURL) = try makeTemporaryStore()
        let newerSchemaFile = AIConnectionsFile(
            updatedAtMs: 7,
            schemaVersion: 2,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .codexCLI,
                    credential: nil,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        try await store.write(newerSchemaFile)
        let originalBytes = try Data(contentsOf: payloadURL)

        let runtimeClient = AiConnectionRuntimeClient(
            verifyProvider: { _, _ in .valid },
            resolveAdapter: { _, _ in nil },
        )
        let client = AiConnectionStatusClient.persistenceClient(
            store: store,
            runtimeClient: runtimeClient,
        )
        let status = await client.checkStatus(.chatgptCodex)

        XCTAssertEqual(status, .notConfigured)
        XCTAssertEqual(try Data(contentsOf: payloadURL), originalBytes)
    }

    private func makeTemporaryStore() throws -> (AIConnectionFileStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatus-\(UUID().uuidString)", isDirectory: true)
        let payloadURL = directory.appendingPathComponent("auth.json")
        let lockURL = directory.appendingPathComponent("auth.lock")
        return (AIConnectionFileStore(payloadURL: payloadURL, lockURL: lockURL), payloadURL)
    }

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
    // CBW-003-stream_contextual_chat_response: concurrent finish는 이미 추출된 item event를 앞지를 수 없다.
    // readability callback에서 추출된 delta/completed 처리 중 termination callback이 진입하는 순서를 검증합니다.
    // - 검증 내용: delta callback이 중단된 동안 finish가 반환하지 않고 completed item 뒤 terminal snapshot을 만듭니다.
    // - 사전 조건: delta와 completed는 한 append에서 추출되고 turn/completed는 newline 없이 buffer에 남아 있습니다.
    // - 기대 결과: finish는 append 처리 후 완료되며 authoritative completed text를 반환합니다.

    // CBW-003-stream_contextual_chat_response: unique empty agent item 수는 protocol limit을 넘을 수 없다.
    // text가 없는 item도 ID/order storage를 소비하므로 item count 제한에 포함되는지 검증합니다.
    // - 검증 내용: 129번째 unique agentMessage item이 terminal parsing failure를 만듭니다.
    // - 사전 조건: 서로 다른 ID의 empty item/started notification 129개를 전달합니다.
    // - 기대 결과: driver는 성공 final 대신 classified protocol failure로 종료합니다.

    // CBW-003-stream_contextual_chat_response: stored agent text는 UTF-8 byte budget을 넘을 수 없다.
    // 다중 byte text가 character count가 아니라 UTF-8 storage 기준으로 제한되는지 검증합니다.
    // - 검증 내용: 128 KiB를 초과하는 단일 delta가 terminal parsing failure를 만듭니다.
    // - 사전 조건: 한글 scalar로 기존 total attachment text budget보다 큰 delta를 구성합니다.
    // - 기대 결과: driver는 oversized text를 저장하지 않고 classified protocol failure로 종료합니다.

    // CBW-003-stream_contextual_chat_response: oversized agent item ID는 accumulator에 저장하지 않는다.
    // provider-controlled ID가 order/map storage를 무제한 점유하지 못하도록 UTF-8 길이를 검증합니다.
    // - 검증 내용: 1,025-byte item ID가 terminal parsing failure를 만듭니다.
    // - 사전 조건: ASCII 1,025자로 구성한 agentMessage item/started notification을 전달합니다.
    // - 기대 결과: driver는 item을 등록하지 않고 classified protocol failure로 종료합니다.

    // CBW-003-stream_contextual_chat_response: completed text 교체는 same-item delta storage를 즉시 해제한다.
    // authoritative completion 이후 남은 total budget을 다른 item delta가 사용할 수 있는지 검증합니다.
    // - 검증 내용: full-budget delta를 짧은 completion으로 교체한 뒤 두 번째 item이 남은 budget을 사용합니다.
    // - 사전 조건: 첫 item delta는 128 KiB이고 completion은 1 byte, 두 번째 delta는 나머지 budget입니다.
    // - 기대 결과: storage 합계가 budget 이내로 유지되고 final은 두 authoritative item 순서로 반환됩니다.

    // CBW-003-stream_contextual_chat_response: 최대 stored-text payload는 JSON escaping 후에도 허용된다.
    // 유효한 128 KiB delta가 raw-line envelope 제한에 선행 차단되지 않는지 검증합니다.

    // CBW-003-stream_contextual_chat_response: newline 없는 raw JSON line은 byte cap을 넘을 수 없다.
    // JSON parsing 전 stdout buffer가 provider-controlled payload로 무제한 증가하지 않는지 검증합니다.

    // CBW-003-stream_contextual_chat_response: retained stderr는 byte cap 초과 시 protocol을 종료한다.
    // subprocess stderr가 종료 전까지 무제한 누적되지 않고 분류된 resource failure를 만드는지 검증합니다.

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

    // MARK: - CBW-003-stream_contextual_chat_response

    /// CBW-003-stream_contextual_chat_response: Codex execution request reuses one working directory snapshot.
    /// Codex executor에 전달되는 working directory와 readable paths가 같은 scope 계산 결과를 사용하는지 검증합니다.
    /// - 검증 내용: executor request가 canonical folder와 선택 readable path를 함께 보존하는지 확인합니다.
    /// - 사전 조건: locked folder context와 provider-managed Codex payload가 준비되어 있습니다.
    /// - 기대 결과: request의 workingDirectory와 readablePaths가 folder scope 계산에 일치합니다.
    func testCodexStream_passesWorkingDirectoryAndReadablePathsTogether() async throws {
        let folder = "/tmp/cbw003-codex-folder"
        let selectedPath = "\(folder)/Selected.swift"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try Data("selected".utf8).write(to: URL(fileURLWithPath: selectedPath))
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let payload = makeCodexPayload(requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(references: [
                AiChatContextReference(
                    kind: .reference,
                    identifier: folder,
                    metadata: ["route": "folder", "path": folder],
                ),
            ]),
            parts: [AiChatLockedContextPartSnapshot(
                source: .currentContext,
                resolution: .providerNativeFile(
                    kind: .codexPathScope,
                    mimeType: "text/plain",
                    metadata: ["path": selectedPath],
                ),
                fileKind: .file,
                canonicalPath: selectedPath,
                displayPath: "Selected.swift",
            )],
        ))
        let preflight = AiChatProviderPreflightResult(payload: payload, credential: .providerManaged)
        nonisolated(unsafe) var captured: CodexExecutionRequest?

        let stream = AiChatProviderExecutionClient.codexStream(
            context: payload.fallbackExecutionContext,
            preflight: preflight,
            now: { 1 },
            executor: { request, _ in
                captured = request
                return "answer"
            },
        )
        _ = try await collectCBW003Events(stream)

        XCTAssertEqual(captured?.workingDirectory?.path, folder)
        XCTAssertEqual(captured?.readablePaths.map(\.path), [selectedPath])
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

    // CBW-003-prepare_contextual_chat_request: Codex permission profile은 root deny 후 선택 경로만 재허용한다.
    // project root 전체가 아니라 isolated session cwd와 선택 파일만 read entry가 되는지 검증합니다.

    // CBW-003-prepare_contextual_chat_request: Codex session home과 cwd는 생성 직후 실경로로 확정한다.
    // process 환경과 cwd가 symlink alias가 아닌 permission profile의 canonical path를 공유하는지 검증합니다.

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

    /// CBW-003-stream_contextual_chat_response: only agent message updates expose assistant deltas.
    /// Codex item.updated의 provider item type을 exact allowlist로 제한하는지 검증합니다.
    /// - 검증 내용: reasoning, command, missing type은 무시되고 snake/camel agent message만 delta가 됩니다.
    /// - 사전 조건: 네 종류의 item.updated JSONL frame이 제공됩니다.
    /// - 기대 결과: 두 agent message variant만 agentMessageDelta를 생성합니다.
    func testCodexCompatibilityMapper_itemUpdatedOnlyMapsAgentMessages() throws {
        let result = try CodexExecTestHarness.feed([
            #"{"type":"item.updated","item_id":"reasoning","item_type":"reasoning","delta":"internal reasoning"}"#,
            #"{"type":"item.updated","item_id":"tool","item_type":"command_execution","delta":"tool command"}"#,
            #"{"type":"item.updated","item_id":"missing","delta":"missing type"}"#,
            #"{"type":"item.updated","item_id":"snake","item_type":"agent_message","delta":"hello"}"#,
            #"{"type":"item.updated","item_id":"camel","item_type":"agentMessage","delta":" world"}"#,
        ])
        let mapped = result.events.compactMap { outcome -> CodexAppServerEvent? in
            guard case let .event(event) = outcome else { return nil }
            return CodexExecCompatibilityMapper.map(event)
        }
        XCTAssertEqual(mapped, [
            .agentMessageDelta(itemID: "snake", delta: "hello"),
            .agentMessageDelta(itemID: "camel", delta: " world"),
        ])
    }

    /// CBW-003-stream_contextual_chat_response: command execution evidence stays internal and non-assistant.
    /// nested command_execution status와 exit_code를 activity로 보존하되 assistant text로 노출하지 않는지 검증합니다.
    /// - 검증 내용: valid evidence mapping, absent exit code, invalid nested types/status, and no assistant delta.
    /// - 사전 조건: command_execution item.started/item.completed JSONL frames가 제공됩니다.
    /// - 기대 결과: typed evidence만 payload에 남고 mapper는 command activity만 생성합니다.
    func testCodexDecoder_commandExecutionEvidenceIsBoundedAndNotAssistantText() throws {
        let result = try CodexExecTestHarness.feed([
            #"{"type":"item.started","item":{"id":"command-started","type":"command_execution","status":"started"}}"#,
            #"{"type":"item.updated","item":{"id":"command-progress","type":"command_execution","status":"inProgress"}}"#,
            #"{"type":"item.completed","item":{"id":"command","type":"command_execution","status":"completed", "#
                + #""exit_code":7,"text":"do not expose"}}"#,
            #"{"type":"item.completed","item":{"id":"command-failed","type":"command_execution","status":"failed","exit_code":1}}"#,
        ])
        guard case let .event(started) = result.events[0],
              case let .event(progress) = result.events[1],
              case let .event(completed) = result.events[2],
              case let .event(failed) = result.events[3]
        else {
            XCTFail("expected decoded command events")
            return
        }
        XCTAssertEqual(started.payload.commandExecutionEvidence?.status, .started)
        XCTAssertNil(started.payload.commandExecutionEvidence?.exitCode)
        XCTAssertEqual(progress.payload.commandExecutionEvidence?.status, .inProgress)
        XCTAssertEqual(completed.payload.commandExecutionEvidence?.status, .completed)
        XCTAssertEqual(completed.payload.commandExecutionEvidence?.exitCode, 7)
        XCTAssertEqual(failed.payload.commandExecutionEvidence?.status, .failed)
        XCTAssertEqual(failed.payload.commandExecutionEvidence?.exitCode, 1)
        XCTAssertEqual(CodexExecCompatibilityMapper.map(completed), .itemCompleted(
            id: "command", kind: .commandExecution, completedText: nil, providerEventType: "item.completed",
        ))
    }

    /// CBW-003-stream_contextual_chat_response: invalid command execution evidence fails closed.
    /// command_execution에 한정해 status/exit_code의 typed contract를 강제하는지 검증합니다.
    /// - 검증 내용: wrong status type, unknown status, fractional and out-of-range exit code를 확인합니다.
    /// - 사전 조건: malformed nested command_execution frames가 각각 제공됩니다.
    /// - 기대 결과: 각 frame은 malformedFrame으로 거부되고 다른 item contract는 변경되지 않습니다.
    func testCodexDecoder_invalidCommandExecutionEvidenceIsMalformed() {
        let invalidFrames = [
            #"{"type":"item.started","item":{"type":"command_execution","status":true}}"#,
            #"{"type":"item.started","item":{"type":"command_execution","status":"unknown"}}"#,
            #"{"type":"item.started","item":{"type":"command_execution","exit_code":1.5}}"#,
            #"{"type":"item.started","item":{"type":"command_execution","exit_code":2147483648}}"#,
        ]
        for frame in invalidFrames {
            var decoder = CodexExecJSONLDecoder()
            XCTAssertThrowsError(try decoder.append(Data((frame + "\n").utf8))) { error in
                XCTAssertEqual(error as? CodexExecDecodeError, .malformedFrame)
            }
        }
    }

    /// CBW-003-prepare_contextual_chat_request: legacy Codex requests without a folder use an isolated session cwd.
    /// Home, Recents, and collection requests must execute through the provider-owned session directory.
    /// - 검증 내용: shared controller spawn, CODEX_HOME/session cwd와 안전한 read-only argv를 확인합니다.
    /// - 사전 조건: folder scope root가 없는 legacy Codex request와 fake process가 제공됩니다.
    /// - 기대 결과: launchFailed 없이 final assistant text를 반환하고 provider process는 한 번만 spawn됩니다.
    func testCodexLegacyWithoutFolder_usesProviderOwnedReadOnlySession() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-codex-home", isDirectory: true)
        try? FileManager.default.removeItem(at: codexHome)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let process = CodexExecFakeProcess(stdout: [
            Data(#"{"type":"thread.started","thread_id":"legacy-thread"}"#.utf8),
            Data(#"{"type":"item.updated","item_id":"message","item_type":"agentMessage","delta":"legacy "}"#
                .utf8),
            Data(#"{"type":"item.completed","item":{"id":"message","type":"agentMessage","text":"legacy answer"}}"#
                .utf8),
            Data(#"{"type":"turn.completed","turn_id":"turn","status":"completed"}"#.utf8),
        ], stderr: [], terminationStatus: 0)
        let runner = CodexExecFakeRunner(process: process)
        let recorder = CodexExecCommandRecorder()
        let preparer = CodexLegacySessionPreparer { _, arguments, environment in
            XCTAssertEqual(environment.count, 4)
            if arguments.first == "init" {
                XCTAssertEqual(Array(arguments.prefix(3)), ["init", "--quiet", "--initial-branch=voyager-session"])
                try FileManager.default.createDirectory(
                    at: codexHome.appendingPathComponent("session/.git"),
                    withIntermediateDirectories: true,
                )
            }
            if arguments.first == "init" {
                return ""
            }
            if arguments.contains("--is-inside-work-tree") {
                return "true\n"
            }
            return codexHome.appendingPathComponent("session/.git").path + "\n"
        }
        let composition = CodexExecLiveComposition(
            controller: CodexExecProcessController(runner: { command in
                await recorder.record(command)
                return try await runner.run(command)
            }),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            legacySessionPreparer: preparer,
        )
        let events = CodexExecAppServerEventRecorder()
        let result = try await composition.executeLegacy(
            request: CodexExecutionRequest(
                runID: "legacy-no-folder", model: "gpt-5-codex", prompt: "prompt", thinking: .effort(.high),
            ),
            onEvent: { events.append($0) },
        )
        XCTAssertEqual(result, "legacy answer")
        XCTAssertEqual(events.events, [
            .agentMessageDelta(itemID: "message", delta: "legacy "),
            .itemCompleted(
                id: "message",
                kind: .agentMessage(phase: nil),
                completedText: "legacy answer",
                providerEventType: "item.completed",
            ),
            .turnCompleted(
                turnID: "turn",
                status: .completed,
                failure: nil,
                providerEventType: "turn.completed",
            ),
        ])
        XCTAssertEqual(runner.runCount, 1)
        let recordedCommands = await recorder.commands
        let command = try XCTUnwrap(recordedCommands.last)
        XCTAssertEqual(command.arguments, [
            "exec", "--model", "gpt-5-codex", "-c", "model_reasoning_effort=\"high\"",
            "--json", "--color", "never", "--strict-config", "--ignore-user-config",
            "-c", "default_permissions=\"voyager-reference\"",
            "-c",
            "permissions.voyager-reference.filesystem={\"/tmp/voyager-cbw003-codex-home/session\"=\"read\",\":minimal\"=\"read\",\":root\"=\"deny\"}",
            "--sandbox", "read-only", "-C", codexHome.appendingPathComponent("session").path, "-",
        ])
        XCTAssertFalse(command.arguments.contains("--add-dir"))
        XCTAssertFalse(command.arguments.contains("danger-full-access"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexHome.appendingPathComponent("session").path))
    }

    /// CBW-003-prepare_contextual_chat_request: folder-based legacy Codex execution prepares the provider session
    /// first.
    /// The requested folder remains the process working directory while provider-owned session state is prepared before
    /// readiness.
    /// - 검증 내용: preparer 호출 1회, 준비된 session TMPDIR, 요청 folder `-C`, secret-free environment, process spawn 1회를 확인합니다.
    /// - 사전 조건: 실제 folder working directory와 fake Codex process, readiness probe, legacy session preparer가 주입되어 있습니다.
    /// - 기대 결과: credential 접근/복사 없이 provider-owned session이 준비되고 folder scope로 legacy 실행이 완료됩니다.
    func testCodexLegacyWithFolder_preparesProviderSessionBeforeLaunch() async throws {
        let suffix = UUID().uuidString
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-folder-codex-home-", isDirectory: true)
            .appendingPathComponent(suffix, isDirectory: true)
        let workingDirectory = URL(fileURLWithPath: "/tmp/voyager-cbw003-folder-working-directory-", isDirectory: true)
            .appendingPathComponent(suffix, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: codexHome)
            try? FileManager.default.removeItem(at: workingDirectory)
        }

        let process = CodexExecFakeProcess(stdout: [
            Data(#"{"type":"thread.started","thread_id":"legacy-folder"}"#.utf8),
            Data(#"{"type":"item.completed","item":{"id":"message","type":"agentMessage","text":"folder answer"}}"#
                .utf8),
            Data(#"{"type":"turn.completed","turn_id":"turn","status":"completed"}"#.utf8),
        ], stderr: [], terminationStatus: 0)
        let runner = CodexExecFakeRunner(process: process)
        let recorder = CodexExecCommandRecorder()
        let preparerCalls = CodexExecInvocationCounter()
        let preparer = CodexLegacySessionPreparer { _, arguments, _ in
            if arguments.first == "init" {
                preparerCalls.increment()
                try FileManager.default.createDirectory(
                    at: codexHome.appendingPathComponent("session/.git"),
                    withIntermediateDirectories: true,
                )
                return ""
            }
            if arguments.contains("--is-inside-work-tree") {
                return "true\n"
            }
            return codexHome.appendingPathComponent("session/.git").path + "\n"
        }
        let probe = CodexExecCommandTestHarness()
        let composition = CodexExecLiveComposition(
            controller: CodexExecProcessController(runner: { command in
                await recorder.record(command)
                return try await runner.run(command)
            }),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe(runner: probe.runner),
            legacySessionPreparer: preparer,
        )

        let result = try await composition.executeLegacy(
            request: CodexExecutionRequest(
                runID: "legacy-folder", model: "gpt-5-codex", prompt: "prompt", thinking: .effort(.high),
                workingDirectory: workingDirectory,
            ),
            onEvent: { _ in },
        )

        XCTAssertEqual(result, "folder answer")
        XCTAssertEqual(preparerCalls.value, 1)
        XCTAssertEqual(runner.runCount, 1)
        let recordedCommands = await recorder.commands
        let command = try XCTUnwrap(recordedCommands.last)
        XCTAssertEqual(command.arguments.suffix(2), ["--skip-git-repo-check", "-"])
        XCTAssertEqual(
            try command.arguments[XCTUnwrap(command.arguments.firstIndex(of: "-C")) + 1],
            workingDirectory.path,
        )
        XCTAssertTrue(command.arguments.contains("--skip-git-repo-check"))
        XCTAssertEqual(command.environment["TMPDIR"], codexHome.appendingPathComponent("session").path)
        XCTAssertEqual(Set(command.environment.keys), ["CODEX_HOME", "HOME", "LANG", "PATH", "SHELL", "TMPDIR"])
        XCTAssertTrue(probe.invocations
            .allSatisfy { $0.environment["TMPDIR"] == codexHome.appendingPathComponent("session").path })
        XCTAssertNil(command.environment["OPENAI_API_KEY"])
        XCTAssertNil(command.environment["CODEX_ACCESS_TOKEN"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: codexHome.appendingPathComponent("auth.json").path))
    }

    /// CBW-003-stream_contextual_chat_response: legacy execution preserves a duplicate after completion.
    /// raw event stream failure가 cached completed result보다 우선하는지 검증합니다.
    /// - 검증 내용: first terminal completed 뒤 duplicate terminal이 legacy transportError로 매핑되는지 확인합니다.
    /// - 사전 조건: shared controller가 completed terminal과 후속 failed terminal을 순서대로 수신합니다.
    /// - 기대 결과: final text를 성공으로 반환하지 않고 한 번 spawn/terminate/cleanup하며 registry가 비워집니다.
    func testCodexLegacy_firstCompletedThenDuplicateFailure_preservesRawStreamFailure() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-legacy-duplicate-completed", isDirectory: true)
        try? FileManager.default.removeItem(at: codexHome)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let registry = CodexExecProcessRegistry()
        let controller = CodexExecProcessController(
            runner: runner.run,
            registry: registry,
        )
        let composition = CodexExecLiveComposition(
            controller: controller,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            legacySessionPreparer: makeFakeLegacySessionPreparer(codexHome: codexHome),
        )

        let execution = Task {
            try await composition.executeLegacy(
                request: CodexExecutionRequest(
                    runID: "legacy-duplicate-completed", model: "gpt-5-codex", prompt: "prompt", thinking: nil,
                ),
                onEvent: { _ in },
            )
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"legacy-duplicate-completed"}"#)
        runner.send(#"{"type":"item.updated","item_id":"message","item_type":"agentMessage","delta":"final"}"#)
        runner.send(#"{"type":"turn.completed","turn_id":"turn","status":"completed"}"#)
        runner.send(#"{"type":"turn.failed","turn_id":"turn","status":"failed"}"#)
        runner.finishStreams()
        do {
            _ = try await execution.value
            XCTFail("duplicate terminal must fail legacy execution")
        } catch let error as CodexCLIExecutionError {
            XCTAssertEqual(error, .protocolFailure(.transportError))
        }
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// CBW-003-stream_contextual_chat_response: legacy execution preserves a failure before completion.
    /// first failed terminal이 후속 completed terminal보다 우선하는지 검증합니다.
    /// - 검증 내용: duplicate terminal raw failure가 cached failed result을 transportError로 유지하는지 확인합니다.
    /// - 사전 조건: shared controller가 failed terminal과 후속 completed terminal을 순서대로 수신합니다.
    /// - 기대 결과: legacy execution은 성공 text를 반환하지 않고 한 번만 process state를 정리합니다.
    func testCodexLegacy_firstFailedThenDuplicateCompletion_preservesRawStreamFailure() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-legacy-duplicate-failed", isDirectory: true)
        try? FileManager.default.removeItem(at: codexHome)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecControlledRunner(process: process)
        let registry = CodexExecProcessRegistry()
        let controller = CodexExecProcessController(
            runner: runner.run,
            registry: registry,
        )
        let composition = CodexExecLiveComposition(
            controller: controller,
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            legacySessionPreparer: makeFakeLegacySessionPreparer(codexHome: codexHome),
        )

        let execution = Task {
            try await composition.executeLegacy(
                request: CodexExecutionRequest(
                    runID: "legacy-duplicate-failed", model: "gpt-5-codex", prompt: "prompt", thinking: nil,
                ),
                onEvent: { _ in },
            )
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"legacy-duplicate-failed"}"#)
        runner.send(#"{"type":"turn.failed","turn_id":"turn","message":"failed"}"#)
        runner.send(#"{"type":"turn.completed","turn_id":"turn","status":"completed"}"#)
        runner.finishStreams()
        do {
            _ = try await execution.value
            XCTFail("duplicate terminal must fail legacy execution")
        } catch let error as CodexCLIExecutionError {
            XCTAssertEqual(error, .protocolFailure(.transportError))
        }
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
        let counts = await controller.debugRegistryCounts()
        XCTAssertEqual(counts.fresh, 0)
    }

    /// CBW-003-stream_contextual_chat_response: completed terminal with non-zero exit maps to CLI unavailability.
    /// processFailed terminal result가 legacy execution에서 invalidRequest로 축소되지 않는지 검증합니다.
    /// - 검증 내용: completed JSONL 뒤 status 17 종료가 `.protocolFailure(.cliUnavailable)`로 매핑되는지 확인합니다.
    /// - 사전 조건: controlled fake Codex process가 thread.started와 turn.completed를 보낸 뒤 non-zero로 종료합니다.
    /// - 기대 결과: legacy execution은 성공 text나 invalidRequest가 아닌 typed cliUnavailable failure를 반환합니다.
    func testCodexLegacy_completedNonzeroExit_mapsProcessFailureToCLIUnavailable() async throws {
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-legacy-completed-nonzero", isDirectory: true)
        try? FileManager.default.removeItem(at: codexHome)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 17)
        let runner = CodexExecControlledRunner(process: process)
        let composition = CodexExecLiveComposition(
            controller: CodexExecProcessController(runner: runner.run),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
            legacySessionPreparer: makeFakeLegacySessionPreparer(codexHome: codexHome),
        )

        let execution = Task {
            try await composition.executeLegacy(
                request: CodexExecutionRequest(
                    runID: "legacy-completed-nonzero", model: "gpt-5-codex", prompt: "prompt", thinking: nil,
                ),
                onEvent: { _ in },
            )
        }
        await runner.waitUntilReady()
        runner.send(#"{"type":"thread.started","thread_id":"legacy-completed-nonzero"}"#)
        runner.send(#"{"type":"turn.completed","turn_id":"turn","status":"completed"}"#)
        runner.finishStreams()

        do {
            _ = try await execution.value
            XCTFail("completed terminal with non-zero exit must fail legacy execution")
        } catch let error as CodexCLIExecutionError {
            XCTAssertEqual(error, .protocolFailure(.cliUnavailable))
        }
        XCTAssertEqual(process.terminationCount, 1)
        XCTAssertEqual(process.cleanupCount, 1)
    }

    /// CBW-003-stream_contextual_chat_response: legacy failed terminal diagnostics use the existing Codex classifier.
    /// failed provider event의 내부 diagnostics가 legacy execution에서 typed failure reason으로 분류되는지 검증합니다.
    /// - 검증 내용: auth, network, rate-limit, quota, model-unavailable marker가 각각 기존 분류기로 매핑되는지 확인합니다.
    /// - 사전 조건: 각 marker를 포함한 failed terminal event를 반환하는 fake Codex process를 사용합니다.
    /// - 기대 결과: legacy execution이 marker별 `protocolFailure` reason을 반환합니다.
    func testCodexLegacy_failedTerminalDiagnostics_mapThroughExistingClassifier() async throws {
        let cases: [(marker: String, reason: AiChatExecutionFailure)] = [
            ("Unauthorized: login required", .authentication),
            ("error sending request for url: offline", .network),
            ("rate limit exceeded", .rateLimited),
            ("account quota exceeded", .quotaExceeded),
            ("model not found", .modelUnavailable),
        ]

        for (index, failureCase) in cases.enumerated() {
            let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-legacy-classifier-\(index)", isDirectory: true)
            try? FileManager.default.removeItem(at: codexHome)
            defer { try? FileManager.default.removeItem(at: codexHome) }
            let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
            let runner = CodexExecControlledRunner(process: process)
            let composition = CodexExecLiveComposition(
                controller: CodexExecProcessController(runner: runner.run),
                executableURL: URL(fileURLWithPath: "/tmp/codex"),
                codexHome: codexHome,
                readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                    arguments == ["--version"]
                        ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                        : .init(exitCode: 0, stdout: "", stderr: "")
                },
                legacySessionPreparer: makeFakeLegacySessionPreparer(codexHome: codexHome),
            )

            let execution = Task {
                try await composition.executeLegacy(
                    request: CodexExecutionRequest(
                        runID: "legacy-classifier-\(index)", model: "gpt-5-codex", prompt: "prompt", thinking: nil,
                    ),
                    onEvent: { _ in },
                )
            }
            await runner.waitUntilReady()
            runner
                .send(#"{"type":"thread.started","thread_id":"legacy-classifier"} "#
                    .trimmingCharacters(in: .whitespaces))
            runner
                .send(#"{"type":"turn.failed","turn_id":"turn","status":"failed","message":""# + failureCase
                    .marker + #""}"#)
            runner.finishStreams()

            do {
                _ = try await execution.value
                XCTFail("failed terminal must fail legacy execution")
            } catch let error as CodexCLIExecutionError {
                XCTAssertEqual(error, .protocolFailure(failureCase.reason))
            }
        }
    }

    /// CBW-003-prepare_contextual_chat_request: legacy session symlink escapes are rejected before spawn.
    /// The final `CODEX_HOME/session` canonical path must remain contained after directory creation.
    /// - 검증 내용: 외부 대상 symlink가 typed launch failure를 만들고 runner spawn 및 외부 변경이 없는지 확인합니다.
    /// - 사전 조건: canonical CODEX_HOME/session symlink가 별도 external directory를 가리킵니다.
    /// - 기대 결과: legacy execution은 launchFailed로 종료되고 provider process는 0회 실행됩니다.
    func testCodexLegacyWithoutFolder_rejectsSessionSymlinkEscapeBeforeSpawn() async throws {
        let suffix = UUID().uuidString
        let codexHome = URL(fileURLWithPath: "/tmp/voyager-cbw003-codex-home-")
            .appendingPathComponent(suffix, isDirectory: true)
        let external = URL(fileURLWithPath: "/tmp/voyager-cbw003-external-")
            .appendingPathComponent(suffix, isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let session = codexHome.appendingPathComponent("session", isDirectory: true)
        guard symlink(external.path, session.path) == 0 else { throw POSIXError(.EIO) }
        defer {
            _ = unlink(session.path)
            _ = rmdir(codexHome.path)
            _ = rmdir(external.path)
        }

        let process = CodexExecFakeProcess(stdout: [], stderr: [], terminationStatus: 0)
        let runner = CodexExecFakeRunner(process: process)
        let composition = CodexExecLiveComposition(
            controller: CodexExecProcessController(runner: runner.run),
            executableURL: URL(fileURLWithPath: "/tmp/codex"),
            codexHome: codexHome,
            readinessProbe: CodexExecReadinessProbe { _, arguments, _ in
                arguments == ["--version"]
                    ? .init(exitCode: 0, stdout: "codex-cli 0.148.0\n", stderr: "")
                    : .init(exitCode: 0, stdout: "", stderr: "")
            },
        )

        do {
            _ = try await composition.executeLegacy(
                request: CodexExecutionRequest(
                    runID: "legacy-symlink-escape", model: "gpt-5-codex", prompt: "prompt", thinking: nil,
                ),
                onEvent: { _ in },
            )
            XCTFail("session symlink escape must fail")
        } catch {
            XCTAssertEqual(error as? CodexCLIExecutionError, .launchFailed)
        }
        XCTAssertEqual(runner.runCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.path), [])
    }

    // CBW-003-prepare_contextual_chat_request: App Server는 선택 permission profile 적용을 증명해야 한다.
    // legacy 또는 profile fallback 응답이 turn 실행으로 이어지지 않고 fail-closed 되는지 검증합니다.

    // CBW-003-prepare_contextual_chat_request: symlink session 경로는 App Server 계약 전체에서 실경로로 정규화한다.
    // permission profile, thread cwd, 응답 검증이 동일한 canonical path를 사용하는지 검증합니다.

    // CBW-003-prepare_contextual_chat_request: 검증된 제한 profile만 Codex turn을 시작한다.
    // profile·sandbox·approval·cwd·runtime root가 모두 일치할 때 turn/start가 전송되는지 검증합니다.
}

private extension CBW003ProviderExecutionResolutionTests {
    func makeFakeLegacySessionPreparer(codexHome: URL) -> CodexLegacySessionPreparer {
        CodexLegacySessionPreparer { _, arguments, _ in
            if arguments.first == "init" {
                try FileManager.default.createDirectory(
                    at: codexHome.appendingPathComponent("session/.git"),
                    withIntermediateDirectories: true,
                )
            }
            if arguments.first == "init" {
                return ""
            }
            if arguments.contains("--is-inside-work-tree") {
                return "true\n"
            }
            return codexHome.appendingPathComponent("session/.git").path + "\n"
        }
    }

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

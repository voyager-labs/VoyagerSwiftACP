import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderPreflightTests: XCTestCase {
    func testPrepare_nilCredential_failsAuthenticationBeforeNetwork() {
        let request = makeRequest(provider: .openai, capability: .effort(values: [.high], defaultValue: nil))

        XCTAssertThrowsError(try AiChatProviderPreflight.prepare(request, credential: nil)) { error in
            XCTAssertEqual(error as? AiChatProviderPreflightError, .missingCredential(.openai))
        }
    }

    func testPrepare_openAIWrongCredentialKind_failsAuthentication() {
        let request = makeRequest(provider: .openai, capability: .effort(values: [.high], defaultValue: nil))

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

    func testPrepare_usesSelectedModelRawModelIDNotDisplayName() throws {
        let request = makeRequest(
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

    func testPrepare_openAIThinkingLoweringMatrix() throws {
        let capability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: nil)

        let omitted = try AiChatProviderPreflight.prepare(
            makeRequest(provider: .openai, selectedThinking: nil, capability: capability),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )
        XCTAssertNil(omitted.payload.thinking)
        XCTAssertTrue(omitted.warnings.isEmpty)

        let unsupportedNone = try AiChatProviderPreflight.prepare(
            makeRequest(provider: .openai, selectedThinking: AiThinkingSelection.none, capability: capability),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )
        XCTAssertNil(unsupportedNone.payload.thinking)
        XCTAssertEqual(unsupportedNone.warnings.count, 1)

        let supportedNone = try AiChatProviderPreflight.prepare(
            makeRequest(
                provider: .openai,
                selectedThinking: AiThinkingSelection.none,
                capability: capability,
                supportsThinkingNone: true,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )
        XCTAssertEqual(supportedNone.payload.thinking, AiChatProviderThinkingPayload.none)
        XCTAssertTrue(supportedNone.warnings.isEmpty)

        let effort = try AiChatProviderPreflight.prepare(
            makeRequest(provider: .openai, selectedThinking: AiThinkingSelection.effort(.high), capability: capability),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )
        XCTAssertEqual(effort.payload.thinking, .effort(.high))

        let tokenBudget = try AiChatProviderPreflight.prepare(
            makeRequest(
                provider: .openai,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: capability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )
        XCTAssertNil(tokenBudget.payload.thinking)
        XCTAssertEqual(
            tokenBudget.warnings,
            [
                .omittedThinkingSelection(
                    provider: .openai,
                    selection: .tokenBudget(1024),
                    reason: "The model capability does not advertise token-budget thinking.",
                )
            ],
        )
    }

    func testPrepare_codexThinkingLoweringMatrix() throws {
        let capability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: .low)

        let unsupportedNone = try AiChatProviderPreflight.prepare(
            makeRequest(provider: .chatgptCodex, selectedThinking: AiThinkingSelection.none, capability: capability),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertNil(unsupportedNone.payload.thinking)
        XCTAssertEqual(unsupportedNone.warnings.count, 1)

        let supportedNone = try AiChatProviderPreflight.prepare(
            makeRequest(
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
            makeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.effort(.high),
                capability: capability,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertEqual(effort.payload.thinking, .effort(.high))

        let tokenBudget = try AiChatProviderPreflight.prepare(
            makeRequest(
                provider: .chatgptCodex,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: capability,
            ),
            credential: .oauth(OAuthCredentialFile(accessToken: "codex-token")),
        )
        XCTAssertNil(tokenBudget.payload.thinking)
        XCTAssertEqual(tokenBudget.warnings.count, 1)
    }

    func testPrepare_anthropicThinkingLoweringMatrix_respectsCapabilityKinds() throws {
        let effortCapability = AiModelThinkingCapability.effort(values: [.low, .high], defaultValue: nil)
        let none = try AiChatProviderPreflight.prepare(
            makeRequest(
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
            makeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: manualBudgetCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(budget.payload.thinking, .tokenBudget(1024))

        let adaptiveCapability = AiModelThinkingCapability.adaptive(effortValues: [.low, .high], defaultValue: .low)
        let adaptiveEffort = try AiChatProviderPreflight.prepare(
            makeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.effort(.high),
                capability: adaptiveCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(adaptiveEffort.payload.thinking, .adaptive(defaultEffort: .high))
        XCTAssertEqual(adaptiveEffort.warnings.count, 1)

        let adaptiveBudget = try AiChatProviderPreflight.prepare(
            makeRequest(
                provider: .anthropic,
                selectedThinking: AiThinkingSelection.tokenBudget(1024),
                capability: adaptiveCapability,
            ),
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )
        XCTAssertEqual(adaptiveBudget.payload.thinking, .adaptive(defaultEffort: .low))
        XCTAssertEqual(adaptiveBudget.warnings.count, 1)
    }

    func testPrepare_requestAndSessionSnapshotsDoNotPersistSecretMaterial() throws {
        let apiKeySecret = "sk-super-secret"
        let oauthToken = "oauth-top-secret"
        let requestSnapshot = AiChatRequestContextSnapshot(
            requestID: AiChatRequestID(rawValue: UUID()),
            runID: AiChatRunID(rawValue: UUID()),
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-5.5"),
            selectedThinking: AiThinkingSelection.effort(.high),
            sessionStatus: .idle,
            currentContext: .init(summary: "No secrets should persist here"),
            promptSummary: "No secrets in prompt",
            submittedAtMs: 99,
        )
        let sessionSnapshot = AiChatSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID()),
            status: .active,
            provider: .chatgptCodex,
            model: AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5-codex"),
            selectedThinking: AiThinkingSelection.none,
            transcriptHistory: [AiChatMessage(role: .user, content: "No secrets")],
            updatedAtMs: 100,
        )

        let encodedRequest = try XCTUnwrap(String(data: JSONEncoder().encode(requestSnapshot), encoding: .utf8))
        let encodedSession = try XCTUnwrap(String(data: JSONEncoder().encode(sessionSnapshot), encoding: .utf8))

        for encoded in [encodedRequest, encodedSession] {
            XCTAssertFalse(encoded.contains(apiKeySecret))
            XCTAssertFalse(encoded.contains(oauthToken))
            XCTAssertFalse(encoded.contains("StoredCredentialPayload"))
            XCTAssertFalse(encoded.contains("APIKeyCredentialFile"))
            XCTAssertFalse(encoded.contains("OAuthCredentialFile"))
        }
    }

    func testExecutionFailureMapper_coversAuthModelNetworkTransportAndCancellation() {
        let cases: [(AiHTTPError, AiChatExecutionFailure)] = [
            (.httpError(statusCode: 401, body: "{}"), .authentication),
            (.httpError(statusCode: 404, body: "model not found"), .modelUnavailable),
            (.httpError(statusCode: 400, body: "{\"error\":\"model unavailable\"}"), .modelUnavailable),
            (.timeout, .network),
            (.networkError("The Internet connection appears to be offline."), .network),
            (.networkError("Socket closed unexpectedly"), .transportError),
            (.cancelled, .cancelled),
            (.httpError(statusCode: 429, body: "usage limit reached"), .quotaExceeded),
            (.httpError(statusCode: 400, body: "monthly limit reached for this plan"), .quotaExceeded),
            (
                .httpError(
                    statusCode: 429,
                    body: "You exceeded your current quota, please check your plan and billing details",
                ),
                .quotaExceeded,
            )
        ]

        for (error, expectedFailure) in cases {
            XCTAssertEqual(AiChatProviderExecutionFailureMapper.map(error), expectedFailure)
        }
    }
}

private extension AiChatProviderPreflightTests {
    func makeRequest(
        provider: AiProvider,
        modelHandle: AiModelHandle? = nil,
        selectedModel: AiProviderModel? = nil,
        selectedThinking: AiThinkingSelection? = AiThinkingSelection.none,
        capability: AiModelThinkingCapability? = nil,
        supportsThinkingNone: Bool = false,
    ) -> AiChatRequest {
        let resolvedModel = selectedModel ?? AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: modelHandle?.rawValue ?? "test-model"),
            provider: provider,
            rawModelID: modelHandle?.rawValue ?? "test-model",
            displayName: "Test Model",
            providerDisplayName: "Provider",
            thinkingCapability: capability ?? .unknown(reason: AiThinkingUnavailableReason(message: "unknown")),
            supportsThinkingNone: supportsThinkingNone,
            unavailableReason: nil,
        )
        let handle = modelHandle ?? AiModelHandle(provider: provider, rawValue: "handle-model")

        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                provider: provider,
                model: handle,
                selectedModel: resolvedModel,
                selectedThinking: selectedThinking,
                sessionStatus: .idle,
                currentContext: .init(summary: "Current context"),
                promptSummary: "Prompt summary",
                submittedAtMs: 1,
            ),
            messages: [AiChatMessage(role: .user, content: "Ping")],
        )
    }
}

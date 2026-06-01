import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderPreflightTests: XCTestCase {
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
            ),
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

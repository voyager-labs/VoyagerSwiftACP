@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiProviderModelListClientTests: XCTestCase {
    override func tearDown() {
        ModelListURLProtocol.reset()
        super.tearDown()
    }

    func testLoadModels_chatgptCodex_fetchesOAuthBackedCodexModelsAndThinkingMetadata() async throws {
        let client = makeLiveClient { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "chatgpt.com")
            XCTAssertEqual(request.url?.path, "/backend-api/codex/models")
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let clientVersion = queryItems.first { $0.name == "client_version" }?.value
            XCTAssertNotNil(clientVersion)
            XCTAssertNotEqual(clientVersion, "voyager")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer codex-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
            XCTAssertEqual(request.value(forHTTPHeaderField: "version"), clientVersion)
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "codex_cli_rs/\(clientVersion!) (macOS)")
            return makeHTTPResponse(
                statusCode: 200,
                json: """
                {
                  "models": [
                    {
                      "slug": "gpt-5.5",
                      "display_name": "GPT-5.5",
                      "supported_reasoning_levels": [
                        { "effort": "low", "description": "Low" },
                        { "effort": "medium", "description": "Medium" },
                        { "effort": "high", "description": "High" }
                      ],
                      "default_reasoning_level": "medium",
                      "hidden": false
                    },
                    {
                      "slug": "gpt-5.3-codex-spark",
                      "display_name": "GPT-5.3 Codex Spark",
                      "hidden": false
                    },
                    {
                      "slug": "gpt-5.4",
                      "display_name": "GPT-5.4",
                      "hidden": true
                    }
                  ]
                }
                """
            )
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: "account-123"))
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.5", "gpt-5.3-codex-spark"])
        XCTAssertEqual(models.map(\.displayName), ["GPT-5.5", "GPT-5.3 Codex Spark"])
        XCTAssertEqual(models.map(\.provider), Array(repeating: .chatgptCodex, count: 2))
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high], defaultValue: .medium),
                .unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API.")),
            ]
        )
        XCTAssertEqual(ModelListURLProtocol.requestCount, 1)
    }

    func testLoadModels_chatgptCodex_acceptsAppServerModelShapeAndFiltersVisibilityNone() async throws {
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 200,
                json: """
                {
                  "data": [
                    {
                      "id": "preset-gpt-5.5",
                      "model": "gpt-5.5",
                      "displayName": "GPT-5.5",
                      "hidden": true,
                      "supportedReasoningEfforts": [
                        { "reasoningEffort": "minimal", "description": "Minimal" },
                        { "reasoningEffort": "xhigh", "description": "Extra high" }
                      ],
                      "defaultReasoningEffort": "xhigh"
                    },
                    {
                      "id": "internal-disabled",
                      "model": "internal-disabled",
                      "displayName": "Internal Disabled",
                      "visibility": "none"
                    },
                    {
                      "model": "gpt-5.4-mini",
                      "display_name": "GPT-5.4 mini",
                      "supported_reasoning_efforts": ["low", "medium", "high"],
                      "default_reasoning_effort": "medium"
                    }
                  ]
                }
                """
            )
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: nil))
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.4-mini"])
        XCTAssertEqual(models.map(\.displayName), ["GPT-5.4 mini"])
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high], defaultValue: .medium),
            ]
        )
    }

    func testLoadModels_chatgptCodex_usesOnlyEndpointReturnedModelsWithoutCanonicalInjection() async throws {
        let client = makeLiveClient { _ in
            makeHTTPResponse(
                statusCode: 200,
                json: """
                {
                  "models": [
                    {
                      "slug": "gpt-5.2",
                      "display_name": "gpt-5.2"
                    }
                  ]
                }
                """
            )
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: nil))
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.2"])
        XCTAssertEqual(models.map(\.displayName), ["gpt-5.2"])
        XCTAssertEqual(models.map(\.thinkingCapability), [.unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API."))])
        XCTAssertTrue(models.allSatisfy { $0.provider == .chatgptCodex })
    }

    func testLoadModels_openAI_usesModelAPIResponseAndLeavesThinkingUnknownWhenMetadataIsAbsent() async throws {
        let client = makeLiveClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai")
            return makeHTTPResponse(
                statusCode: 200,
                json: """
                {
                  "data": [
                    { "id": "gpt-4.1" },
                    { "id": "o4-mini" },
                    { "id": "custom-openai-model" }
                  ]
                }
                """
            )
        }

        let models = try await client.loadModels(
            .openai,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        )

        XCTAssertEqual(models.map(\.id.rawValue), ["gpt-4.1", "o4-mini", "custom-openai-model"])
        XCTAssertEqual(models.map(\.displayName), ["gpt-4.1", "o4-mini", "custom-openai-model"])
        XCTAssertEqual(models.map(\.thinkingCapability), [.unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API.")), .unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API.")), .unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API."))])
    }

    func testLoadModels_anthropic_usesCapabilitiesFromModelAPIForThinkingMetadata() async throws {
        let client = makeLiveClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            return makeHTTPResponse(
                statusCode: 200,
                json: """
                {
                  "data": [
                    {
                      "id": "claude-sonnet-4-5",
                      "display_name": "Claude Sonnet 4.5",
                      "capabilities": {
                        "thinking": {
                          "supported": true,
                          "types": {
                            "enabled": { "supported": true }
                          }
                        },
                        "effort": {
                          "supported": true,
                          "low": { "supported": true },
                          "medium": { "supported": true },
                          "high": { "supported": true },
                          "xhigh": { "supported": false },
                          "max": { "supported": true }
                        }
                      }
                    },
                    {
                      "id": "claude-adaptive",
                      "display_name": "Claude Adaptive",
                      "capabilities": {
                        "thinking": {
                          "supported": true,
                          "types": {
                            "adaptive": { "supported": true }
                          }
                        },
                        "effort": {
                          "supported": false,
                          "low": { "supported": true },
                          "high": { "supported": true }
                        }
                      }
                    },
                    { "id": "claude-custom" }
                  ]
                }
                """
            )
        }

        let models = try await client.loadModels(
            .anthropic,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant"))
        )

        XCTAssertEqual(models.map(\.providerDisplayName), ["Anthropic", "Anthropic", "Anthropic"])
        XCTAssertEqual(models.map(\.displayName), ["Claude Sonnet 4.5", "Claude Adaptive", "claude-custom"])
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high, .max], defaultValue: nil),
                .adaptive(effortValues: [.low, .high], defaultValue: nil),
                .unknown(reason: AiThinkingUnavailableReason(message: "Thinking capability metadata was not provided by the model API.")),
            ]
        )
        XCTAssertEqual(models.map(\.unavailableReason), [nil, nil, nil])
    }

    func testLoadModels_openAI_withMissingCredential_throwsTypedError() async {
        let client = makeLiveClient { _ in
            XCTFail("Missing credential must fail before network")
            throw URLError(.badServerResponse)
        }

        do {
            _ = try await client.loadModels(.openai, nil)
            XCTFail("Expected missingCredential")
        } catch let error as AiProviderModelListError {
            XCTAssertEqual(error, .missingCredential(.openai))
            XCTAssertEqual(ModelListURLProtocol.requestCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThinkingCapability_supportsPlanNeutralShapesWithoutProviderPayloads() {
        XCTAssertEqual(AiThinkingEffort.allCases, [.minimal, .low, .medium, .high, .xhigh, .max])
        XCTAssertEqual(AiThinkingSelection.effort(.medium), .effort(.medium))
        XCTAssertEqual(AiThinkingSelection.tokenBudget(2048), .tokenBudget(2048))
        XCTAssertEqual(
            AiModelThinkingCapability.effort(values: [.low, .medium], defaultValue: .medium),
            .effort(values: [.low, .medium], defaultValue: .medium)
        )
        XCTAssertEqual(
            AiModelThinkingCapability.adaptive(effortValues: [.minimal, .high], defaultValue: .high),
            .adaptive(effortValues: [.minimal, .high], defaultValue: .high)
        )
        XCTAssertEqual(
            AiModelThinkingCapability.tokenBudget(min: 0, max: 4096, defaultValue: 1024),
            .tokenBudget(min: 0, max: 4096, defaultValue: 1024)
        )
    }

    private func makeLiveClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AiProviderModelListClient {
        ModelListURLProtocol.reset()
        ModelListURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelListURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return .live(session: session)
    }
}

private final class ModelListURLProtocol: URLProtocol, @unchecked Sendable {
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

    override class func canInit(with _: URLRequest) -> Bool {
        count += 1
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
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

private func makeHTTPResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let url = URL(string: "https://example.com")!
    let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    return (response, Data(json.utf8))
}

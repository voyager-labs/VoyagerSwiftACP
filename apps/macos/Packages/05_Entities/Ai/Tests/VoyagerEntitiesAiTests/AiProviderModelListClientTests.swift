@preconcurrency import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiProviderModelListClientTests: XCTestCase {
    override func tearDown() {
        ModelListURLProtocol.reset()
        super.tearDown()
    }
}

extension AiProviderModelListClientTests {
    func testLoadModels_chatgptCodex_fetchesOAuthBackedCodexModelsAndThinkingMetadata() async throws {
        let client = makeLiveClient { request in
            try assertCodexRequestMatchesCLIIdentity(request)
            return makeHTTPResponse(statusCode: 200, json: codexModelsWithThinkingJSON())
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: "account-123")),
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.5", "gpt-5.3-codex-spark"])
        XCTAssertEqual(models.map(\.displayName), ["GPT-5.5", "GPT-5.3 Codex Spark"])
        XCTAssertEqual(models.map(\.provider), Array(repeating: .chatgptCodex, count: 2))
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high], defaultValue: .medium),
                kUnknownThinkingCapability,
            ],
        )
        XCTAssertEqual(models.map(\.supportsThinkingNone), [true, false])
        XCTAssertEqual(ModelListURLProtocol.requestCount, 1)
    }

    func testLoadModels_chatgptCodex_acceptsAppServerModelShapeAndFiltersVisibilityNone() async throws {
        let client = makeLiveClient { _ in
            makeHTTPResponse(statusCode: 200, json: codexAppServerModelsJSON())
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: nil)),
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.4-mini"])
        XCTAssertEqual(models.map(\.displayName), ["GPT-5.4 Mini"])
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high], defaultValue: .medium),
            ],
        )
        XCTAssertEqual(models.map(\.supportsThinkingNone), [false])
    }

    func testLoadModels_chatgptCodex_usesOnlyEndpointReturnedModelsWithoutCanonicalInjection() async throws {
        let client = makeLiveClient { _ in
            makeHTTPResponse(statusCode: 200, json: codexSingleModelJSON())
        }

        let models = try await client.loadModels(
            .chatgptCodex,
            .oauth(OAuthCredentialFile(accessToken: "codex-token", chatGPTAccountId: nil)),
        )

        XCTAssertEqual(models.map(\.rawModelID), ["gpt-5.2"])
        XCTAssertEqual(models.map(\.displayName), ["GPT-5.2"])
        XCTAssertEqual(models.map(\.thinkingCapability), [kUnknownThinkingCapability])
        XCTAssertTrue(models.allSatisfy { $0.provider == .chatgptCodex })
    }
}

extension AiProviderModelListClientTests {
    func testLoadModels_openAI_infersReasoningMetadataFromAPIModelIdentifiers() async throws {
        let client = makeLiveClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai")
            return makeHTTPResponse(statusCode: 200, json: openAIModelsJSON())
        }

        let models = try await client.loadModels(
            .openai,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )

        XCTAssertEqual(
            models.map(\.id.rawValue),
            ["gpt-4.1", "gpt-5.1", "gpt-5-pro", "gpt-5.5", "o4-mini", "custom-openai-model"],
        )
        XCTAssertEqual(
            models.map(\.displayName),
            ["GPT-4.1", "GPT-5.1", "GPT-5 Pro", "GPT-5.5", "o4-mini", "custom-openai-model"],
        )
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                kUnknownThinkingCapability,
                .effort(values: [.low, .medium, .high], defaultValue: nil),
                .effort(values: [.high], defaultValue: .high),
                .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium),
                .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium),
                kUnknownThinkingCapability,
            ],
        )
        XCTAssertEqual(models.map(\.supportsThinkingNone), [false, true, false, true, false, false])
    }

    func testLoadModels_openAI_prefersReturnedReasoningMetadataWhenPresent() async throws {
        let client = makeLiveClient { _ in
            makeHTTPResponse(statusCode: 200, json: openAIModelsWithReasoningMetadataJSON())
        }

        let models = try await client.loadModels(
            .openai,
            .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
        )

        XCTAssertEqual(models.map(\.id.rawValue), ["gpt-5.5", "custom-reasoning-model"])
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .high], defaultValue: .high),
                .effort(values: [.minimal, .medium], defaultValue: nil),
            ],
        )
        XCTAssertEqual(models.map(\.supportsThinkingNone), [true, false])
    }

    func testLoadModels_anthropic_usesCapabilitiesFromModelAPIForThinkingMetadata() async throws {
        let client = makeLiveClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            return makeHTTPResponse(statusCode: 200, json: anthropicModelsJSON())
        }

        let models = try await client.loadModels(
            .anthropic,
            .apiKey(APIKeyCredentialFile(secret: "sk-ant")),
        )

        XCTAssertEqual(models.map(\.providerDisplayName), ["Anthropic", "Anthropic", "Anthropic"])
        XCTAssertEqual(models.map(\.displayName), ["Claude Sonnet 4.5", "Claude Adaptive", "claude-custom"])
        XCTAssertEqual(
            models.map(\.thinkingCapability),
            [
                .effort(values: [.low, .medium, .high, .max], defaultValue: nil),
                .adaptive(effortValues: [.low, .high], defaultValue: nil),
                kUnknownThinkingCapability,
            ],
        )
        XCTAssertEqual(models.map(\.unavailableReason), [nil, nil, nil])
        XCTAssertEqual(models.map(\.supportsThinkingNone), [true, false, false])
    }
}

extension AiProviderModelListClientTests {
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
        XCTAssertEqual(AiThinkingSelection.none, .none)
        XCTAssertEqual(AiThinkingSelection.effort(.medium), .effort(.medium))
        XCTAssertEqual(AiThinkingSelection.tokenBudget(2048), .tokenBudget(2048))
        XCTAssertEqual(
            AiModelThinkingCapability.effort(values: [.low, .medium], defaultValue: .medium),
            .effort(values: [.low, .medium], defaultValue: .medium),
        )
        XCTAssertEqual(
            AiModelThinkingCapability.adaptive(effortValues: [.minimal, .high], defaultValue: .high),
            .adaptive(effortValues: [.minimal, .high], defaultValue: .high),
        )
        XCTAssertEqual(
            AiModelThinkingCapability.tokenBudget(min: 0, max: 4096, defaultValue: 1024),
            .tokenBudget(min: 0, max: 4096, defaultValue: 1024),
        )
    }
}

private extension AiProviderModelListClientTests {
    func makeLiveClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
    ) -> AiProviderModelListClient {
        ModelListURLProtocol.reset()
        ModelListURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelListURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return .live(session: session)
    }
}

private let kUnknownThinkingCapability = AiModelThinkingCapability.unknown(
    reason: AiThinkingUnavailableReason(
        message: "Thinking capability metadata was not provided by the model API.",
    ),
)

private func assertCodexRequestMatchesCLIIdentity(_ request: URLRequest) throws {
    XCTAssertEqual(request.url?.scheme, "https")
    XCTAssertEqual(request.url?.host, "chatgpt.com")
    XCTAssertEqual(request.url?.path, "/backend-api/codex/models")
    let queryItems = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    let clientVersion = queryItems.first { $0.name == "client_version" }?.value
    XCTAssertEqual(clientVersion, "0.0.0")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer codex-token")
    XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "account-123")
    XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
    XCTAssertEqual(request.value(forHTTPHeaderField: "version"), "0.0.0")
    let userAgent = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
    XCTAssertTrue(userAgent.hasPrefix("codex_cli_rs/0.0.0 (macOS "))
    XCTAssertTrue(userAgent.contains("; "))
    XCTAssertTrue(userAgent.hasSuffix(")"))
}

private final class ModelListURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var currentHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { currentHandler }
        set { currentHandler = newValue }
    }

    static var requestCount: Int {
        count
    }

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

private func makeHTTPResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
    let url = URL(fileURLWithPath: "/model-list-response")
    let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        ?? HTTPURLResponse()
    return (response, Data(json.utf8))
}

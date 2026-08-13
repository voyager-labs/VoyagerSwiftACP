import Foundation
import VoyagerEntitiesAi
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class ProviderAwareQueryConverterAutoFallbackTests: XCTestCase {
    func testAutoFallbackTriesNextProviderAfterExecutionFailure() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
            .anthropic: [Self.makeModel(provider: .anthropic, rawModelID: "claude-3-5-sonnet")],
        ])
        let converter = Self.makeConverter(fileBox: fileBox, modelLoader: modelLoader)

        let result = await converter.convert(request: Self.makeAutoFallbackRequest())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.fallbackReuse)
        XCTAssertEqual(result.providerId, AiProvider.anthropic.rawValue)
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
        XCTAssertEqual(modelLoader.loadCount(for: .anthropic), 1)
    }

    func testExplicitProviderSelectionIgnoresSearchingStatusBeforeFinal() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeStatusThenFinalExecutionClient(),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, .generatedChangeSet)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.conditions, [])
    }

    func testExplicitProviderSelectionBuildsRequestWithSelectedModelThinkingAndResponseContract() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let model = Self.makeModel(
            provider: .openai,
            rawModelID: "gpt-4o-mini",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
            supportsThinkingNone: true,
        )
        let modelLoader = ModelLoadRecorder(responses: [.openai: [model]])
        let capture = AiChatRequestCaptureBox()
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeCapturingExecutionClient(capture: capture),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .effort("high"),
            ),
        ))

        XCTAssertNil(result.error)
        let request = capture.request
        XCTAssertEqual(request?.context.selectedModel, model)
        XCTAssertEqual(request?.context.selectedThinking, .effort(.high))
        XCTAssertEqual(request?.responseContract, QueryConversionConfig.responseContract)
    }

    func testExplicitModelSelectionBuildsRequestWithRequestedModel() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let model = Self.makeModel(provider: .openai, rawModelID: "gpt-4o")
        let modelLoader = ModelLoadRecorder(responses: [.openai: [model]])
        let capture = AiChatRequestCaptureBox()
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeCapturingExecutionClient(capture: capture),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .specific(provider: AiProvider.openai.rawValue, model: "gpt-4o"),
                thinking: .providerDefault,
            ),
        ))

        XCTAssertNil(result.error)
        XCTAssertEqual(capture.request?.context.model, AiModelHandle(provider: .openai, rawValue: "gpt-4o"))
        XCTAssertEqual(capture.request?.context.selectedModel, model)
    }

    func testExplicitProviderSelectionReturnsCollectionSearchProviderUnavailableForInvalidProvider() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(
                    provider: .openai,
                    rawModelID: "gpt-4o-mini",
                ),
            ],
        ])
        let converter = Self.makeConverter(fileBox: fileBox, modelLoader: modelLoader)

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific("bogus"),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .providerUnavailable)
        XCTAssertEqual(result.providerId, "bogus")
        XCTAssertEqual(result.errorCode, "COLLECTION_SEARCH_PROVIDER_UNAVAILABLE")
        XCTAssertEqual(result.reason, "invalidProvider")
    }

    func testExplicitProviderSelectionMapsExpiredCredentialToExpiredSessionGuidance() async {
        let file = Self.makeConnectionsFile(
            updatedAtMs: 1,
            openAIState: .connectionFailed,
            openAIReason: .expired,
        )
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [:])
        let converter = Self.makeConverter(fileBox: fileBox, modelLoader: modelLoader)

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .invalidCredential)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.errorCode, "AI_PROVIDER_INVALID_CREDENTIAL")
        XCTAssertEqual(result.reason, ProviderStatusReason.expired.rawValue)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("expired"), true)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("reconnect"), true)
    }

    func testExplicitProviderSelectionMapsNetworkUnavailableToNetworkGuidance() async {
        let file = Self.makeConnectionsFile(
            updatedAtMs: 1,
            openAIState: .connectionFailed,
            openAIReason: .networkUnavailable,
        )
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [:])
        let converter = Self.makeConverter(fileBox: fileBox, modelLoader: modelLoader)

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .networkFailure)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.errorCode, "AI_PROVIDER_NETWORK_FAILURE")
        XCTAssertEqual(result.reason, ProviderStatusReason.networkUnavailable.rawValue)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("network"), true)
    }

    func testExecutionAuthenticationMapsToReconnectGuidance() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeFailureExecutionClient(.authentication),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .invalidCredential)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.errorCode, "AI_PROVIDER_INVALID_CREDENTIAL")
        XCTAssertEqual(result.reason, AiChatExecutionFailure.authentication.rawValue)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("authentication"), true)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("reconnect"), true)
    }

    func testExecutionNetworkMapsToNetworkGuidance() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeFailureExecutionClient(.network),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .networkFailure)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.errorCode, "AI_PROVIDER_NETWORK_FAILURE")
        XCTAssertEqual(result.reason, AiChatExecutionFailure.network.rawValue)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("network"), true)
    }

    func testExecutionCLIUnavailableMapsToCodexCLIAvailabilityGuidance() async {
        let file = Self.makeCodexConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .chatgptCodex: [Self.makeModel(provider: .chatgptCodex, rawModelID: "gpt-5")],
        ])
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeFailureExecutionClient(.cliUnavailable),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.chatgptCodex.rawValue),
                model: .auto,
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .providerUnavailable)
        XCTAssertEqual(result.providerId, AiProvider.chatgptCodex.rawValue)
        XCTAssertEqual(result.errorCode, "AI_PROVIDER_UNAVAILABLE")
        XCTAssertEqual(result.reason, AiChatExecutionFailure.cliUnavailable.rawValue)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("codex cli"), true)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("installed"), true)
    }

    func testCodexModelListHTTP401MapsToExpiredReconnectGuidance() {
        assertCodexModelListAuthFailure(statusCode: 401)
    }

    func testCodexModelListHTTP403MapsToExpiredReconnectGuidance() {
        assertCodexModelListAuthFailure(statusCode: 403)
    }

    func testAPIKeyModelListHTTP401MapsToAuthenticationGuidance() {
        assertAPIKeyModelListAuthFailure(statusCode: 401)
    }

    func testAPIKeyModelListHTTP403MapsToAuthenticationGuidance() {
        assertAPIKeyModelListAuthFailure(statusCode: 403)
    }

    func testModelListHTTP500RemainsNetworkFailure() {
        assertModelListHTTPFailure(statusCode: 500, expectedCode: "AI_PROVIDER_NETWORK_FAILURE")
    }

    func testExplicitModelSelectionReturnsCollectionSearchModelUnavailableWhenPreferredModelIsMissing() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(
                    provider: .openai,
                    rawModelID: "gpt-4o-mini",
                ),
            ],
        ])
        let converter = Self.makeConverter(fileBox: fileBox, modelLoader: modelLoader)

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .specific(provider: AiProvider.openai.rawValue, model: "missing-model"),
                thinking: .providerDefault,
            ),
        ))

        XCTAssertEqual(result.outcome, .providerUnavailable)
        XCTAssertEqual(result.providerId, AiProvider.openai.rawValue)
        XCTAssertEqual(result.errorCode, "COLLECTION_SEARCH_MODEL_UNAVAILABLE")
        XCTAssertEqual(result.reason, "modelUnavailable:missing-model")
    }

    func testExplicitSelectionNormalizesUnsupportedStaleThinkingToProviderDefault() async {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let model = Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")
        let modelLoader = ModelLoadRecorder(responses: [.openai: [model]])
        let capture = AiChatRequestCaptureBox()
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: modelLoader,
            executionClient: Self.makeCapturingExecutionClient(capture: capture),
        )

        let result = await converter.convert(request: Self.makeRequest(
            settings: CollectionSearchAISettingsPayload(
                provider: .specific(AiProvider.openai.rawValue),
                model: .auto,
                thinking: .effort("high"),
            ),
        ))

        XCTAssertNil(result.error)
        XCTAssertNil(capture.request?.context.selectedThinking)
    }

    private static func makeConverter(
        fileBox: ConnectionFileBox,
        modelLoader: ModelLoadRecorder,
        executionClient: AiChatProviderExecutionClient = makeFallbackExecutionClient(),
    ) -> ProviderAwareQueryConverter {
        ProviderAwareQueryConverter(
            queryConversionInterpreter: QueryConversionInterpreter(),
            connectionsFileClient: fileBox.client,
            providerExecutionClient: executionClient,
            modelCatalogCache: AIProviderModelCatalogCache(
                connectionsFileClient: fileBox.client,
                modelListClient: modelLoader.client,
            ),
        )
    }

    private func assertCodexModelListAuthFailure(statusCode: Int) {
        let result = mappedModelListFailure(statusCode: statusCode, provider: .chatgptCodex)

        XCTAssertEqual(result.errorCode, "AI_PROVIDER_INVALID_CREDENTIAL")
        XCTAssertEqual(result.outcome, .invalidCredential)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("expired"), true)
        XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("reconnect"), true)
    }

    private func assertAPIKeyModelListAuthFailure(statusCode: Int) {
        for provider in [AiProvider.openai, .anthropic] {
            let result = mappedModelListFailure(statusCode: statusCode, provider: provider)

            XCTAssertEqual(result.errorCode, "AI_PROVIDER_INVALID_CREDENTIAL")
            XCTAssertEqual(result.outcome, .invalidCredential)
            XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("authentication"), true)
            XCTAssertEqual(result.error?.localizedCaseInsensitiveContains("expired"), false)
        }
    }

    private func mappedModelListFailure(
        statusCode: Int,
        provider: AiProvider = .openai,
    ) -> QueryConversionResult {
        let fileBox = ConnectionFileBox(Self.makeConnectionsFile(updatedAtMs: 1))
        let converter = Self.makeConverter(
            fileBox: fileBox,
            modelLoader: ModelLoadRecorder(responses: [:]),
        )

        return converter.mappedModelListFailure(
            .httpError(provider: provider, statusCode: statusCode, body: "test"),
            provider: provider,
        )
    }

    private func assertModelListHTTPFailure(statusCode: Int, expectedCode: String) {
        let result = mappedModelListFailure(statusCode: statusCode)
        XCTAssertEqual(result.errorCode, expectedCode)
        XCTAssertEqual(result.outcome, statusCode == 500 ? .networkFailure : .invalidCredential)
    }

    private static func makeFallbackExecutionClient() -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(execute: { request, _ in
            switch request.context.provider {
            case .openai:
                throw AiChatExecutionFailure.network
            case .anthropic:
                return Self.makeSuccessfulStream(for: request)
            default:
                throw AiChatExecutionFailure.unsupportedProvider
            }
        })
    }

    private static func makeFailureExecutionClient(
        _ failure: AiChatExecutionFailure,
    ) -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(execute: { _, _ in
            throw failure
        })
    }

    private static func makeStatusThenFinalExecutionClient() -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(execute: { request, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.status(
                    context: request.context,
                    signal: AiChatExecutionActivitySignal(
                        activityID: AiChatExecutionActivityID(rawValue: "provider-search"),
                        kind: .searching,
                        phase: .began,
                        evidence: AiChatExecutionActivityEvidence(
                            origin: .providerWire,
                            providerEventType: "response.web_search_call.in_progress",
                        ),
                    ),
                ))
                let response = AiChatResponse(
                    context: request.context,
                    assistantMessage: AiChatMessage(
                        role: .assistant,
                        content: #"{"outcome":"generated_change_set","conditions":[],"scopes":null,"error":null}"#,
                    ),
                    completedAtMs: 2,
                )
                continuation.yield(.final(response: response))
                continuation.finish()
            }
        })
    }

    private static func makeCapturingExecutionClient(
        capture: AiChatRequestCaptureBox,
    ) -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(execute: { request, _ in
            capture.store(request)
            return Self.makeSuccessfulStream(for: request)
        })
    }

    nonisolated private static func makeSuccessfulStream(
        for request: AiChatRequest,
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let response = AiChatResponse(
                context: request.context,
                assistantMessage: AiChatMessage(
                    role: .assistant,
                    content: #"{"conditions":[],"scopes":null,"error":null}"#,
                ),
                completedAtMs: 2,
            )
            continuation.yield(.final(response: response))
            continuation.finish()
        }
    }

    private static func makeAutoFallbackRequest() -> SearchRequestPayload {
        SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(
                        propertyKey: "extension",
                        operator: "any",
                        value: .array([.string("txt")]),
                    ),
                ],
            ),
            collectionSearchAISettings: CollectionSearchAISettingsPayload(
                provider: .auto,
                model: .auto,
                thinking: .providerDefault,
            ),
        )
    }

    private static func makeRequest(settings: CollectionSearchAISettingsPayload) -> SearchRequestPayload {
        SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
            collectionSearchAISettings: settings,
        )
    }

    private static func makeConnectionsFile(
        updatedAtMs: Int64,
        openAIState: ProviderConnectionState = .connected,
        openAIReason: ProviderStatusReason = .none,
    ) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: openAIState,
                        lastErrorCode: openAIReason,
                    ),
                ),
                AiProvider.anthropic.rawValue: ProviderRecordFile(
                    providerId: .anthropic,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-anthropic")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    private static func makeCodexConnectionsFile(updatedAtMs: Int64) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: .chatgptCodex,
            providers: [
                AiProvider.chatgptCodex.rawValue: ProviderRecordFile(
                    providerId: .chatgptCodex,
                    authMethod: .oauth,
                    credential: .oauth(OAuthCredentialFile(accessToken: "test-access-token")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    private static func makeModel(
        provider: AiProvider,
        rawModelID: String,
        thinkingCapability: AiModelThinkingCapability = .unsupported(
            reason: AiThinkingUnavailableReason(message: "unsupported"),
        ),
        supportsThinkingNone: Bool = false,
    ) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawModelID),
            provider: provider,
            rawModelID: rawModelID,
            displayName: rawModelID,
            providerDisplayName: provider.rawValue,
            thinkingCapability: thinkingCapability,
            supportsThinkingNone: supportsThinkingNone,
        )
    }
}

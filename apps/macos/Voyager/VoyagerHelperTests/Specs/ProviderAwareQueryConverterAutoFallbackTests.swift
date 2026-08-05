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
                        content: #"{"conditions":[],"scopes":null,"error":null}"#,
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

    private static func makeConnectionsFile(updatedAtMs: Int64) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-openai")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
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

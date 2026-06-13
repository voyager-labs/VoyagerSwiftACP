import Foundation
import VoyagerEntitiesAi
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class FilterSearchQueryBuilderTests: XCTestCase {
    func testScopeNormalizerNormalizesAndDedupesIdenticalScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "  /Users/test/Downloads/  ",
            "/Users/test/Downloads/subfolder",
            "/Users/test/Downloads",
            "",
        ])

        XCTAssertEqual(normalized, ["/Users/test/Downloads", "/Users/test/Downloads/subfolder"])
    }

    func testScopeNormalizerPreservesRootAndExplicitSubScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "/Users/test",
            "/",
            "/Users/test/Downloads",
        ])

        XCTAssertEqual(normalized, ["/Users/test", "/", "/Users/test/Downloads"])
    }

    func testScopeNormalizerExpandsTildeAndPreservesHomeSubScopes() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        let normalized = SearchScopeNormalizer.normalizeScopes([
            "~/Documents",
            homePath + "/Documents/subfolder",
        ])

        XCTAssertEqual(normalized, [homePath + "/Documents", homePath + "/Documents/subfolder"])
    }

    func testScopeNormalizerReturnsEmptyWhenScopesAreBlank() {
        XCTAssertEqual(SearchScopeNormalizer.normalizeScopes(["", "   "]), [])
    }

    func testConditionCompilerEqOnNameStemIncludesBareAndExtensionForms() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "name_stem",
            operator: "eq",
            value: .string("report"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report\""))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report.*\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerRangeOnSizeBuildsInclusiveBounds() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "size",
            operator: "btw",
            value: .array([.number(100), .number(200)]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize >= 100"))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize <= 200"))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerEqOnExtensionUsesMditemAttribute() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "eq",
            value: .string("pdf"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"pdf\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }
}

private extension FilterSearchQueryBuilderTests {
    func makeCompiler() throws -> SpotlightQueryCompiler {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }

    func loadRegistry<T: Decodable>(fileName: String) throws -> T {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = rootURL.appendingPathComponent("shared").appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class SearchQueryServiceTests: XCTestCase {
    func testQuerySearchPreservesExcludedScopesInPlannedFilters() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [
                            SearchConditionPayload(
                                propertyKey: "extension",
                                operator: "eq",
                                value: .string("pdf"),
                            ),
                        ],
                        scopes: ["  /tmp/root  ", "/tmp/root/sub", "   "],
                        error: nil,
                        outcome: .generatedChangeSet,
                        providerId: "openai",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/fallback"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.queryConversion?.outcome, .generatedChangeSet)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root", "/tmp/root/sub"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: true,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("pdf")),
                ],
            ),
        )
    }

    func testQuerySearchForwardsCollectionSearchSettingsToConverter() async {
        let requestBox = RequestCaptureBox()
        let settings = CollectionSearchAISettingsPayload(
            provider: .specific("openai"),
            model: .auto,
            thinking: .providerDefault,
        )
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { request in
                await requestBox.store(request)
                return await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: nil,
                        error: nil,
                        outcome: .generatedChangeSet,
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/fallback"],
                excludedScopes: [],
                includeSubfolders: true,
                conditions: [],
            ),
            collectionSearchAISettings: settings,
        )

        _ = await service.querySearch(request)

        let seenRequest = await requestBox.request
        XCTAssertEqual(seenRequest?.collectionSearchAISettings, settings)
    }

    func testQuerySearchScopeOnlyChangeReportsGeneratedChangeSet() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: ["/tmp/new-root"],
                        error: nil,
                        outcome: .fallbackReuse,
                        providerId: "openai",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "downloads folder",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/old-root"],
                excludedScopes: ["/tmp/old-root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.queryConversion?.outcome, .generatedChangeSet)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/new-root"],
                excludedScopes: ["/tmp/old-root/excluded"],
                includeSubfolders: true,
                conditions: [],
            ),
        )
    }

    func testQuerySearchEmptyQueryPreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                XCTFail("convertQuery should not run for empty query")
                return await MainActor.run {
                    QueryConversionResult(conditions: [], scopes: nil, error: nil, outcome: .generatedChangeSet)
                }
            },
        )
        let request = SearchRequestPayload(
            query: "   ",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertNil(response.error)
        XCTAssertNil(response.queryConversion)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )
    }

    func testQuerySearchErrorResponsePreservesExcludedScopes() async {
        let service = SearchQueryService(
            searchService: SearchExecutionServiceStub(),
            convertQuery: { _ in
                await MainActor.run {
                    QueryConversionResult(
                        conditions: [],
                        scopes: nil,
                        error: "provider failed",
                        outcome: .conversionFailure,
                        providerId: "openai",
                        errorCode: "AI_PROVIDER_UNAVAILABLE",
                        reason: "networkFailure",
                    )
                }
            },
        )
        let request = SearchRequestPayload(
            query: "find receipts",
            filters: SearchFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )

        let response = await service.querySearch(request)

        XCTAssertEqual(response.error, SearchErrorPayload(code: "AI_PROVIDER_UNAVAILABLE", details: "provider failed"))
        XCTAssertEqual(response.queryConversion?.outcome, .conversionFailure)
        XCTAssertEqual(
            response.appliedFilters,
            AppliedFiltersPayload(
                scopes: ["/tmp/root"],
                excludedScopes: ["/tmp/root/excluded"],
                includeSubfolders: false,
                conditions: [
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
                ],
            ),
        )
    }

    func testAppliedFiltersPayloadDecodesMissingExcludedScopesAsDeterministicEmptyArray() throws {
        let data = Data(#"{"scopes":["/tmp/root"],"includeSubfolders":true,"conditions":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(AppliedFiltersPayload.self, from: data)

        XCTAssertEqual(decoded.excludedScopes, [])
    }

    func testQueryConversionInterpreterKeepsValidExtensionConditionAsGeneratedChangeSet() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {
              "conditions":[{"propertyKey":"extension","operator":"any","value":["png","jpg"]}],
              "scopes":null,
              "error":null
            }
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/root"], conditions: []),
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.generatedChangeSet)
        XCTAssertEqual(result.conditions, [
            SearchConditionPayload(
                propertyKey: "extension",
                operator: "any",
                value: .array([.string("png"), .string("jpg")]),
            ),
        ])
    }

    func testQueryConversionInterpreterScopeOnlyChangeIsGeneratedChangeSet() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {"conditions":[],"scopes":["/tmp/new-root"],"error":null}
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/old-root"], conditions: []),
        )

        XCTAssertNil(result.error)
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.generatedChangeSet)
        XCTAssertEqual(result.conditions, [])
        XCTAssertEqual(result.scopes, ["/tmp/new-root"])
    }

    func testQueryConversionInterpreterInvalidGeneratedConditionsReturnConversionFailure() throws {
        let converter = QueryConversionInterpreter()
        let result = try converter.decodeAndNormalize(
            content: #"""
            {
              "conditions":[{"propertyKey":"kind","operator":"eq","value":"image"}],
              "scopes":null,
              "error":null
            }
            """#,
            existingFilters: SearchFiltersPayload(scopes: ["/tmp/root"], conditions: []),
        )

        XCTAssertEqual(result.outcome, .conversionFailure)
        XCTAssertEqual(result.error, "Generated filters could not be validated.")
        XCTAssertEqual(result.conditions, [])
    }
}

@MainActor
final class AIProviderModelCatalogCacheTests: XCTestCase {
    func testSelectedModelUsesFirstQueryConversionModelAndReusesCacheForSameSnapshot() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "text-embedding-ada-002"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-3.5-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-search-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        let first = try await cache.selectedModel(for: selection, file: file)
        let second = try await cache.selectedModel(for: selection, file: file)

        XCTAssertEqual(first.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(second.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelReturnsPreferredExplicitModelWhenAvailable() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)
        let preferredModel = AiModelHandle(provider: .openai, rawValue: "gpt-4o")

        let model = try await cache.selectedModel(
            for: selection,
            file: file,
            preferredModel: preferredModel,
        )

        XCTAssertEqual(model.id, preferredModel)
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelThrowsWhenPreferredExplicitModelIsMissing() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)
        let preferredModel = AiModelHandle(provider: .openai, rawValue: "gpt-4o")

        do {
            _ = try await cache.selectedModel(
                for: selection,
                file: file,
                preferredModel: preferredModel,
            )
            XCTFail("Expected explicit preferred model lookup to fail when missing")
        } catch let error as AIProviderModelCatalogCacheError {
            XCTAssertEqual(error, .modelUnavailable(provider: .openai, model: preferredModel))
        }
    }

    func testSelectedModelInvalidatesCacheWhenConnectionsFileSnapshotChanges() async throws {
        let initialFile = Self.makeConnectionsFile(updatedAtMs: 1)
        let updatedFile = Self.makeConnectionsFile(updatedAtMs: 2)
        let fileBox = ConnectionFileBox(initialFile)
        let modelLoader = ModelLoadRecorder(sequence: [
            [.openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")]],
            [.openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o")]],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let initialSelection = try XCTUnwrap(AIProviderQuerySelection.select(from: initialFile).successValue)
        let updatedSelection = try XCTUnwrap(AIProviderQuerySelection.select(from: updatedFile).successValue)

        let first = try await cache.selectedModel(for: initialSelection, file: initialFile)
        fileBox.set(updatedFile)
        let second = try await cache.selectedModel(for: updatedSelection, file: updatedFile)

        XCTAssertEqual(first.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(second.id.rawValue, "gpt-4o")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 2)
    }

    func testWarmUpCachesConnectedProviderModelsForLaterSelection() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini")],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        try await cache.warmUp()
        let model = try await cache.selectedModel(for: selection, file: file)

        XCTAssertEqual(model.id.rawValue, "gpt-4o-mini")
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
    }

    func testSelectedModelThrowsWhenProviderReturnsOnlyNonGenerativeModels() async throws {
        let file = Self.makeConnectionsFile(updatedAtMs: 1)
        let fileBox = ConnectionFileBox(file)
        let modelLoader = ModelLoadRecorder(responses: [
            .openai: [
                Self.makeModel(provider: .openai, rawModelID: "text-embedding-ada-002"),
                Self.makeModel(provider: .openai, rawModelID: "whisper-1"),
                Self.makeModel(provider: .openai, rawModelID: "omni-moderation-latest"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-3.5-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4-turbo"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-mini-audio-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-search-preview"),
                Self.makeModel(provider: .openai, rawModelID: "gpt-4o-realtime-preview"),
            ],
        ])
        let cache = AIProviderModelCatalogCache(
            connectionsFileClient: fileBox.client,
            modelListClient: modelLoader.client,
        )
        let selection = try XCTUnwrap(AIProviderQuerySelection.select(from: file).successValue)

        do {
            _ = try await cache.selectedModel(for: selection, file: file)
            XCTFail("Expected non-generative OpenAI models to be rejected for query conversion")
        } catch let error as AIProviderModelCatalogCacheError {
            XCTAssertEqual(error, .emptyModelList(provider: .openai))
        }
    }

    private static func makeConnectionsFile(updatedAtMs: Int64) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: updatedAtMs,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "sk-test")),
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
    }

    fileprivate static func makeModel(provider: AiProvider, rawModelID: String) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawModelID),
            provider: provider,
            rawModelID: rawModelID,
            displayName: rawModelID,
            providerDisplayName: provider.rawValue,
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )
    }
}

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
        XCTAssertEqual(result.outcome, QueryConversionResultOutcome.generatedChangeSet)
        XCTAssertEqual(result.providerId, AiProvider.anthropic.rawValue)
        XCTAssertEqual(modelLoader.loadCount(for: .openai), 1)
        XCTAssertEqual(modelLoader.loadCount(for: .anthropic), 1)
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

    private static func makeCapturingExecutionClient(
        capture: AiChatRequestCaptureBox,
    ) -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(execute: { request, _ in
            capture.store(request)
            return Self.makeSuccessfulStream(for: request)
        })
    }

    private nonisolated static func makeSuccessfulStream(
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
                    SearchConditionPayload(propertyKey: "extension", operator: "eq", value: .string("txt")),
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

private final class ConnectionFileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AIConnectionsFile

    init(_ file: AIConnectionsFile) {
        self.file = file
    }

    var client: AIConnectionsFileClient {
        AIConnectionsFileClient(
            load: { [self] in get() },
            save: { .success($0) },
            deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
        )
    }

    func set(_ file: AIConnectionsFile) {
        lock.lock()
        self.file = file
        lock.unlock()
    }

    private func get() -> AIConnectionsFile {
        lock.lock()
        let file = file
        lock.unlock()
        return file
    }
}

private final class ModelLoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[AiProvider: [AiProviderModel]]]
    private var counts: [AiProvider: Int] = [:]

    init(responses: [AiProvider: [AiProviderModel]]) {
        self.responses = [responses]
    }

    init(sequence: [[AiProvider: [AiProviderModel]]]) {
        responses = sequence
    }

    var client: AiProviderModelListClient {
        AiProviderModelListClient(loadModels: { [self] provider, _ in
            loadModels(for: provider)
        })
    }

    func loadCount(for provider: AiProvider) -> Int {
        lock.lock()
        let count = counts[provider, default: 0]
        lock.unlock()
        return count
    }

    private func loadModels(for provider: AiProvider) -> [AiProviderModel] {
        lock.lock()
        let count = counts[provider, default: 0]
        counts[provider] = count + 1
        let responseIndex = min(count, max(responses.count - 1, 0))
        let models = responses[responseIndex][provider, default: []]
        lock.unlock()
        return models
    }
}

private extension Result {
    var successValue: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}

private struct SearchExecutionServiceStub: SearchExecutionServicing {
    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            items: [],
            error: nil,
        )
    }

    func searchRecent(_: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload {
        RecentSearchResponsePayload(items: [])
    }

    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload {
        TagSearchResponsePayload(requestedTag: request.requestedTag, items: [])
    }
}

private final class AiChatRequestCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequest: AiChatRequest?

    var request: AiChatRequest? {
        lock.lock()
        let request = capturedRequest
        lock.unlock()
        return request
    }

    func store(_ request: AiChatRequest) {
        lock.lock()
        capturedRequest = request
        lock.unlock()
    }
}

private actor RequestCaptureBox {
    var request: SearchRequestPayload?

    func store(_ request: SearchRequestPayload) {
        self.request = request
    }
}

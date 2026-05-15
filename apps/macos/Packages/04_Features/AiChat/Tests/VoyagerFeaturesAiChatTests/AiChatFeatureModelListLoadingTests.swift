import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureModelListLoadingTests: XCTestCase {
    func testProviderConnectionUpdatesCancelInFlightBatchAndIgnoreStaleResponse() async {
        actor LoadDriver {
            var startedProviders: [AiProvider] = []
            var cancellationCount = 0

            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                startedProviders.append(provider)

                if startedProviders.count == 1 {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        return makeProviderModels()
                    } catch is CancellationError {
                        cancellationCount += 1
                        throw CancellationError()
                    }
                }

                return [makeProviderModels()[1]]
            }

            func snapshot() -> (startedProviders: [AiProvider], cancellationCount: Int) {
                (startedProviders, cancellationCount)
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let openAIFile = makeConnectionsFile(
            lastUsedProviderId: .openai,
            providers: [makeProviderRecord(provider: .openai, credential: openAICredential)]
        )
        let anthropicFile = makeConnectionsFile(
            updatedAtMs: 2,
            lastUsedProviderId: .anthropic,
            providers: [makeProviderRecord(provider: .anthropic, credential: anthropicCredential)]
        )
        let driver = LoadDriver()
        let firstRequestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let secondRequestID = makeUUID("00000000-0000-0000-0000-000000000001")
        let remainingModel = makeProviderModels()[1]

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(openAIFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = firstRequestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai]
            state.modelListPendingProviders = [.openai]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: firstRequestID,
            provider: .openai,
            credential: openAICredential
        ))

        await store.send(.providerConnectionsUpdated(anthropicFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = secondRequestID
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = [.anthropic]
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: secondRequestID,
            provider: .anthropic,
            credential: anthropicCredential
        ))

        await store.receive(.modelListLoaded(
            requestID: secondRequestID,
            provider: .anthropic,
            models: [remainingModel]
        )) { state in
            state.catalogRows = [catalogRows[1]]
            state.modelListState = .loaded([remainingModel])
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = catalogRows[0].handle
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.anthropic])
            state.availableModelsByProvider = [.anthropic: [remainingModel]]
            state.lastExecutionFailure = nil
        }

        await store.send(.modelListLoaded(
            requestID: firstRequestID,
            provider: .openai,
            models: makeProviderModels()
        ))

        try? await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = await driver.snapshot()
        XCTAssertEqual(snapshot.startedProviders, [.openai, .anthropic])
        XCTAssertEqual(snapshot.cancellationCount, 1)
        XCTAssertEqual(store.state.modelListState, .loaded([remainingModel]))
        XCTAssertEqual(store.state.unavailableSelectedModelHandle, catalogRows[0].handle)
    }

    func testProviderConnectionsUpdatedMergesModelsFromMultipleConnectedProviders() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .anthropic:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    return [makeProviderModels()[1]]
                case .chatgptCodex:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .openai,
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .anthropic, credential: anthropicCredential),
            ]
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let anthropicModels = [makeProviderModels()[1]]
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .anthropic]
            state.modelListPendingProviders = [.openai, .anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .anthropic,
            credential: anthropicCredential
        )) { state in
            state.modelListProvider = .anthropic
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: anthropicModels
        )) { state in
            state.catalogRows = catalogRows
            state.modelListState = .loaded(makeProviderModels())
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [.openai: openAIModels, .anthropic: anthropicModels]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.modelCatalogState.sections.map(\.title), [
            aiChatProviderSectionTitle(for: .openai),
            aiChatProviderSectionTitle(for: .anthropic),
        ])
        XCTAssertEqual(store.state.modelCatalogState.sections.first?.rows.map(\.title), ["GPT-4.1 Mini"])
        XCTAssertNil(store.state.modelCatalogState.sections.first?.rows.first?.providerBadge)
        XCTAssertEqual(store.state.modelCatalogState.sections.last?.rows.first?.providerBadge, "Reasoning-first chat")
    }

    func testModelListPartialFailurePreservesSuccessfulModelsFromAnotherProvider() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .anthropic:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    throw AiProviderModelListError.invalidResponse(.anthropic)
                case .chatgptCodex:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let anthropicCredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-anthropic"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .openai,
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .anthropic, credential: anthropicCredential),
            ]
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let anthropicFailure = AiModelListFailure(message: "Anthropic returned an invalid model list response.")
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .anthropic]
            state.modelListPendingProviders = [.openai, .anthropic]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .anthropic,
            credential: anthropicCredential
        )) { state in
            state.modelListProvider = .anthropic
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.anthropic]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .anthropic,
            failure: anthropicFailure
        )) { state in
            state.catalogRows = [catalogRows[0]]
            state.modelListState = .loaded(openAIModels)
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.anthropic: anthropicFailure]
            state.providerConnectionSnapshot = .known([.openai, .anthropic])
            state.availableModelsByProvider = [.openai: openAIModels, .anthropic: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "GPT-4.1 Mini")
        XCTAssertEqual(store.state.availableModels, openAIModels)
        XCTAssertEqual(store.state.modelListFailedProviders, [.anthropic: anthropicFailure])
    }

    func testModelListCodexFailurePreservesSuccessfulOpenAIModels() async {
        actor LoadDriver {
            func load(provider: AiProvider, credential _: StoredCredentialPayload?) async throws -> [AiProviderModel] {
                switch provider {
                case .openai:
                    try await Task.sleep(nanoseconds: 10_000_000)
                    return [makeProviderModels()[0]]
                case .chatgptCodex:
                    try await Task.sleep(nanoseconds: 20_000_000)
                    throw AiProviderModelListError.unsupportedProvider(.chatgptCodex)
                case .anthropic:
                    return []
                }
            }
        }

        let catalogRows = makeCatalogRows()
        let openAICredential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .openai,
            providers: [
                makeProviderRecord(provider: .openai, credential: openAICredential),
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ]
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let openAIModels = [makeProviderModels()[0]]
        let codexFailure = AiModelListFailure(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider
        )
        let driver = LoadDriver()

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                try await driver.load(provider: provider, credential: credential)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .openai
            state.modelListProviderOrder = [.openai, .chatgptCodex]
            state.modelListPendingProviders = [.openai, .chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.openai, .chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .openai,
            credential: openAICredential
        ))
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential
        )) { state in
            state.modelListProvider = .chatgptCodex
        }
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: openAIModels
        )) { state in
            state.modelListProvider = .openai
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [.openai: openAIModels]
            state.modelListFailedProviders = [:]
        }
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .chatgptCodex,
            failure: codexFailure
        )) { state in
            state.catalogRows = [catalogRows[0]]
            state.modelListState = .loaded(openAIModels)
            state.selectedModelHandle = catalogRows[0].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.chatgptCodex: codexFailure]
            state.providerConnectionSnapshot = .known([.openai, .chatgptCodex])
            state.availableModelsByProvider = [.openai: openAIModels, .chatgptCodex: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.availableModels, openAIModels)
        XCTAssertEqual(store.state.modelListFailedProviders, [.chatgptCodex: codexFailure])
    }

    func testModelListCodexOnlySuccessLoadsCodexModelsAndThinkingMetadata() async {
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .chatgptCodex,
            providers: [
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ]
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let codexModel = AiProviderModel(
            id: AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5.5"),
            provider: .chatgptCodex,
            rawModelID: "gpt-5.5",
            displayName: "GPT-5.5",
            providerDisplayName: ProviderDescriptor.descriptor(for: .chatgptCodex)?.displayName ?? "ChatGPT Codex",
            thinkingCapability: .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium),
            unavailableReason: nil
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            selectedModelHandle: codexModel.id
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, credential in
                XCTAssertEqual(provider, .chatgptCodex)
                XCTAssertEqual(credential, codexCredential)
                return [codexModel]
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = [.chatgptCodex]
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential
        ))
        await store.receive(.modelListLoaded(
            requestID: requestID,
            provider: .chatgptCodex,
            models: [codexModel]
        )) { state in
            state.catalogRows = [AiModelCatalogRow(
                handle: codexModel.id,
                displayName: codexModel.displayName,
                authMethod: .oauth,
                subtitle: nil,
                sortOrder: 0,
                isDefault: false,
                isRecommended: false
            )]
            state.modelListState = .loaded([codexModel])
            state.selectedModelHandle = codexModel.id
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [.chatgptCodex: [codexModel]]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "GPT-5.5")
        XCTAssertEqual(store.state.chatInputDisplayModel.effortLabel, "default")
        XCTAssertEqual(
            store.state.resolvedSelectedModel?.thinkingCapability,
            .effort(values: [.minimal, .low, .medium, .high, .xhigh], defaultValue: .medium)
        )
    }

    func testModelListCodexOnlyFailureTransitionsToFailedStateAndExposesUnsupportedProvider() async {
        let codexCredential = StoredCredentialPayload.oauth(OAuthCredentialFile(accessToken: "codex-token"))
        let connectionsFile = makeConnectionsFile(
            lastUsedProviderId: .chatgptCodex,
            providers: [
                makeProviderRecord(provider: .chatgptCodex, authMethod: .oauth, credential: codexCredential),
            ]
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000000")
        let codexFailure = AiModelListFailure(
            message: "ChatGPT Codex model listing is unavailable.",
            reason: .unsupportedProvider
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, _ in
                XCTAssertEqual(provider, .chatgptCodex)
                throw AiProviderModelListError.unsupportedProvider(.chatgptCodex)
            })
        }

        await store.send(.providerConnectionsUpdated(connectionsFile)) { state in
            state.modelListState = .loading
            state.modelListRequestID = requestID
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = [.chatgptCodex]
            state.modelListPendingProviders = [.chatgptCodex]
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
        }
        await store.receive(.modelListLoading(
            requestID: requestID,
            provider: .chatgptCodex,
            credential: codexCredential
        ))
        await store.receive(.modelListLoadFailed(
            requestID: requestID,
            provider: .chatgptCodex,
            failure: codexFailure
        )) { state in
            state.modelListState = .failed(codexFailure)
            state.modelListRequestID = nil
            state.modelListProvider = .chatgptCodex
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.chatgptCodex: codexFailure]
            state.providerConnectionSnapshot = .known([.chatgptCodex])
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, codexFailure.message)
        XCTAssertEqual(store.state.modelListFailedProviders, [.chatgptCodex: codexFailure])
    }

    func testModelListLoadedKeepsCurrentSelectionWhenStillPresent() async {
        let models = makeProviderModels()
        let catalogRows = makeCatalogRows()
        let requestID = makeUUID("00000000-0000-0000-0000-000000000010")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[1].handle,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic]
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models
        )) { state in
            state.modelListState = .loaded(models)
            state.selectedModelHandle = catalogRows[1].handle
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: models]
            state.lastExecutionFailure = nil
        }
    }

    func testModelListLoadedClearsSelectionWhenCurrentModelIsMissing() async {
        let catalogRows = makeCatalogRows()
        let remainingModel = makeProviderModels()[1]
        let requestID = makeUUID("00000000-0000-0000-0000-000000000020")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[0].handle,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic]
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: [remainingModel]
        )) { state in
            state.catalogRows = [catalogRows[1]]
            state.modelListState = .loaded([remainingModel])
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = catalogRows[0].handle
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: [remainingModel]]
            state.lastExecutionFailure = nil
        }
    }

    func testModelListLoadedKeepsSelectionButClearsIncompatibleThinking() async {
        let models = makeThinkingCapableProviderModels()
        let catalogRows = makeCatalogRows()
        let requestID = makeUUID("00000000-0000-0000-0000-000000000011")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: catalogRows,
            modelListState: .loading,
            selectedModelHandle: catalogRows[1].handle,
            selectedThinking: .effort(.high),
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic]
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: models
        )) { state in
            state.modelListState = .loaded(models)
            state.selectedModelHandle = catalogRows[1].handle
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = nil
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.anthropic: models]
            state.lastExecutionFailure = nil
        }
    }

    func testModelListLoadFailedTransitionsToFailedState() async {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000030")
        let failure = AiModelListFailure(message: "Anthropic model list request failed (500).")
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            modelListState: .loading,
            modelListRequestID: requestID,
            modelListProvider: .anthropic,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic]
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoadFailed(
            requestID: requestID,
            provider: .anthropic,
            failure: failure
        )) { state in
            state.modelListState = .failed(failure)
            state.modelListRequestID = nil
            state.modelListProvider = .anthropic
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [.anthropic: failure]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }
    }

    func testProviderConnectionsUpdatedWithNoConnectedProvidersRestoresUnconnectedState() async {
        let selectedHandle = makeCatalogRows()[0].handle
        let file = makeConnectionsFile(providers: [
            makeProviderRecord(provider: .openai, state: .disconnected),
        ])
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loaded(makeProviderModels()),
            selectedModelHandle: selectedHandle,
            selectedThinking: .effort(.medium)
        )) {
            AiChatFeature()
        }

        await store.send(.providerConnectionsUpdated(file)) { state in
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = selectedHandle
            state.modelListProvider = nil
            state.providerConnectionSnapshot = .known([])
            state.availableModelsByProvider = [:]
            state.lastExecutionFailure = nil
        }

        XCTAssertEqual(store.state.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings"
        )))
        if case let .unconnected(connection, _) = store.state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
        } else {
            XCTFail("Expected unconnected surface state")
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    func testModelListLoadedWithEmptyModelsTransitionsToEmptyState() async {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000040")
        let selectedHandle = makeCatalogRows()[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            catalogRows: makeCatalogRows(),
            modelListState: .loading,
            selectedModelHandle: selectedHandle,
            modelListRequestID: requestID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai]
        )) {
            AiChatFeature()
        }

        await store.send(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: []
        )) { state in
            state.catalogRows = []
            state.modelListState = .empty
            state.selectedModelHandle = nil
            state.selectedThinking = nil
            state.unavailableSelectedModelHandle = selectedHandle
            state.modelListRequestID = nil
            state.modelListProvider = .openai
            state.modelListProviderOrder = []
            state.modelListPendingProviders = []
            state.modelListLoadedModelsByProvider = [:]
            state.modelListFailedProviders = [:]
            state.providerConnectionSnapshot = .unknown
            state.availableModelsByProvider = [.openai: []]
            state.lastExecutionFailure = nil
        }

        XCTAssertFalse(store.state.canSubmit)
        XCTAssertEqual(store.state.chatInputDisplayModel.modelLabel, "No models available")
    }
}

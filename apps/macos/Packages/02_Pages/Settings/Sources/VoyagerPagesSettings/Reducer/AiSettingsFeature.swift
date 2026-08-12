import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection

@Reducer
public struct AiSettingsFeature {
    public typealias State = AiSettingsState
    public typealias Action = AiSettingsAction

    @Dependency(\.aiConnectionsFileClient)
    var connectionsFileClient
    @Dependency(\.aiProviderVerificationClient)
    var verificationClient
    @Dependency(\.collectionSearchAISettingsClient)
    var collectionSearchSettingsClient
    @Dependency(\.aiChatDefaultSettingsClient)
    var chatDefaultSettingsClient
    @Dependency(\.aiProviderModelListClient)
    var providerModelListClient
    @Dependency(\.uuid)
    var uuid

    public init() {}

    private enum CancelID: Hashable {
        case bootstrap
        case collectionSearchModels
        case chatModels
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.didBootstrap else { return .none }
                state.didBootstrap = true
                state.bootstrapPhase = .loading
                let settings = collectionSearchSettingsClient.load()
                let normalized = Self.normalizedCollectionSearchSettings(
                    settings,
                    modelsByProvider: state.collectionSearchModelsByProvider,
                )
                state.collectionSearchSettings = normalized
                state.chatDefaultSettings = chatDefaultSettingsClient.load()
                let settingsSaveEffect: Effect<Action> = normalized != settings
                    ? Self.saveCollectionSearchSettingsEffect(
                        settings: normalized,
                        client: collectionSearchSettingsClient,
                    )
                    : .none
                return .merge(
                    Self.bootstrapEffect(
                        connectionsFileClient: connectionsFileClient,
                        verificationClient: verificationClient,
                    ),
                    settingsSaveEffect,
                )

            case let .bootstrapCompleted(results):
                Self.applyBootstrapResults(results, to: &state)
                state.bootstrapPhase = .loaded
                let collectionEffect = Self.refreshCollectionSearchModelsAfterBootstrapEffect(
                    state: &state,
                    settingsClient: collectionSearchSettingsClient,
                    providerModelListClient: providerModelListClient,
                    connectionsFileClient: connectionsFileClient,
                )
                let chatEffect = Self.refreshChatModelsAfterBootstrapEffect(
                    state: &state,
                    providerModelListClient: providerModelListClient,
                    connectionsFileClient: connectionsFileClient,
                    makeRequestID: { uuid() },
                )
                return .merge(collectionEffect, chatEffect)

            case let .bootstrapVerificationCompleted(results):
                Self.applyBootstrapResults(results, to: &state)
                state.bootstrapPhase = .loaded
                let collectionEffect = Self.refreshCollectionSearchModelsAfterBootstrapEffect(
                    state: &state,
                    settingsClient: collectionSearchSettingsClient,
                    providerModelListClient: providerModelListClient,
                    connectionsFileClient: connectionsFileClient,
                )
                let chatEffect = Self.refreshChatModelsAfterBootstrapEffect(
                    state: &state,
                    providerModelListClient: providerModelListClient,
                    connectionsFileClient: connectionsFileClient,
                    makeRequestID: { uuid() },
                )
                return .merge(collectionEffect, chatEffect)

            case .bootstrapFailed:
                state.bootstrapPhase = .failed
                return .none

            case .retryBootstrapTapped:
                state.bootstrapPhase = .loading
                return Self.bootstrapEffect(
                    connectionsFileClient: connectionsFileClient,
                    verificationClient: verificationClient,
                )

            case let .row(.element(id: _, action: .connectionResponse(result))),
                 let .row(.element(id: _, action: .disconnectResponse(result))):
                let saveEffect = Self.resetCollectionSearchProviderIfDisconnected(
                    result: result,
                    state: &state,
                    client: collectionSearchSettingsClient,
                )
                let chatEffect: Effect<Action>
                if result.state == .connected,
                   result.provider == state.chatSelectedProvider
                {
                    state.rows[id: result.provider]?.connectionState = .connected
                    chatEffect = Self.refreshChatModelsAfterBootstrapEffect(
                        state: &state,
                        providerModelListClient: providerModelListClient,
                        connectionsFileClient: connectionsFileClient,
                        makeRequestID: { uuid() },
                    )
                } else {
                    Self.invalidateChatCatalogIfDisconnected(result: result, state: &state)
                    chatEffect = .none
                }
                return .merge(
                    saveEffect,
                    chatEffect,
                    .send(.delegate(.connectionsFileUpdated(result.updatedFile))),
                )

            case .delegate(.connectionsFileUpdated):
                return .none

            case let .collectionSearchSettingsLoaded(settings):
                let normalized = Self.normalizedCollectionSearchSettings(
                    settings,
                    modelsByProvider: state.collectionSearchModelsByProvider,
                )
                state.collectionSearchSettings = normalized
                if normalized != settings {
                    return Self.saveCollectionSearchSettingsEffect(
                        settings: normalized,
                        client: collectionSearchSettingsClient,
                    )
                }
                return .none

            case let .collectionSearchModelsLoaded(modelsByProvider: modelsByProvider, errorMessage: errorMessage):
                state.collectionSearchModelsByProvider = modelsByProvider
                state.collectionSearchLoadError = errorMessage
                let previousSettings = state.collectionSearchSettings
                let normalized = Self.normalizedCollectionSearchSettings(
                    previousSettings,
                    modelsByProvider: modelsByProvider,
                )
                state.collectionSearchSettings = normalized
                return normalized == previousSettings
                    ? .none
                    : Self.saveCollectionSearchSettingsEffect(
                        settings: normalized,
                        client: collectionSearchSettingsClient,
                    )

            case let .collectionSearchProviderChanged(preference):
                state.collectionSearchSettings.provider = preference
                state.collectionSearchSettings.model = .auto
                state.collectionSearchSettings.thinking = .providerDefault
                let normalized = Self.normalizedCollectionSearchSettings(
                    state.collectionSearchSettings,
                    modelsByProvider: state.collectionSearchModelsByProvider,
                )
                state.collectionSearchSettings = normalized

                let saveEffect = Self.saveCollectionSearchSettingsEffect(
                    settings: normalized,
                    client: collectionSearchSettingsClient,
                )

                guard state.didBootstrap, case let .specific(providerRaw) = normalized.provider,
                      let provider = AiProvider(rawValue: providerRaw)
                else { return saveEffect }

                return .merge(
                    saveEffect,
                    Self.refreshCollectionSearchModelsEffect(
                        provider: provider,
                        providerModelListClient: providerModelListClient,
                        connectionsFileClient: connectionsFileClient,
                    ),
                )

            case let .collectionSearchModelChanged(preference):
                state.collectionSearchSettings.model = preference
                let normalized = Self.normalizedCollectionSearchSettings(
                    state.collectionSearchSettings,
                    modelsByProvider: state.collectionSearchModelsByProvider,
                )
                state.collectionSearchSettings = normalized
                return Self.saveCollectionSearchSettingsEffect(
                    settings: normalized,
                    client: collectionSearchSettingsClient,
                )

            case let .collectionSearchThinkingChanged(preference):
                state.collectionSearchSettings.thinking = preference
                let normalized = Self.normalizedCollectionSearchSettings(
                    state.collectionSearchSettings,
                    modelsByProvider: state.collectionSearchModelsByProvider,
                )
                state.collectionSearchSettings = normalized
                return Self.saveCollectionSearchSettingsEffect(
                    settings: normalized,
                    client: collectionSearchSettingsClient,
                )

            case .collectionSearchResetTapped:
                state.collectionSearchSettings = .default
                return Self.saveCollectionSearchSettingsEffect(
                    settings: .default,
                    client: collectionSearchSettingsClient,
                )

            case let .chatModelsLoaded(provider: provider, requestID: requestID, models: models):
                guard state.chatDefaultSettings.provider?.rawValue == provider.rawValue,
                      state.chatModelRequestID == requestID
                else { return .none }

                state.chatModelsByProvider[provider] = models
                state.chatModelCatalogPhase = .loaded
                state.chatModelRequestID = nil
                state.chatModelLoadError = nil
                return .none

            case let .chatModelsFailed(provider: provider, requestID: requestID, message: message):
                guard state.chatDefaultSettings.provider?.rawValue == provider.rawValue,
                      state.chatModelRequestID == requestID
                else { return .none }

                state.chatModelsByProvider[provider] = nil
                state.chatModelCatalogPhase = .failed
                state.chatModelRequestID = nil
                state.chatModelLoadError = message
                return .none

            case let .chatProviderChanged(selection):
                state.chatDefaultSettings = AiChatDefaultSettings(
                    provider: selection,
                    model: nil,
                    thinking: .providerDefault,
                )
                state.chatModelRequestID = nil
                state.chatModelLoadError = nil
                let saveEffect = Self.saveChatDefaultSettingsEffect(
                    settings: state.chatDefaultSettings,
                    client: chatDefaultSettingsClient,
                )

                guard state.didBootstrap,
                      let provider = AiProvider(rawValue: selection.rawValue),
                      state.rows[id: provider]?.connectionState == .connected
                else {
                    state.chatModelCatalogPhase = .idle
                    return saveEffect
                }

                let requestID = uuid()
                state.chatModelsByProvider[provider] = nil
                state.chatModelCatalogPhase = .loading
                state.chatModelRequestID = requestID
                return .merge(
                    saveEffect,
                    Self.refreshChatModelsEffect(
                        provider: provider,
                        requestID: requestID,
                        providerModelListClient: providerModelListClient,
                        connectionsFileClient: connectionsFileClient,
                    ),
                )

            case let .chatModelChanged(selection):
                guard selection.providerRawValue == state.chatDefaultSettings.provider?.rawValue,
                      let model = state.chatAvailableModels.first(where: {
                          $0.rawModelID == selection.modelRawValue || $0.id.rawValue == selection.modelRawValue
                      })
                else { return .none }

                state.chatDefaultSettings.model = selection
                let normalizedThinking = AiThinkingSelectionPolicy.normalize(
                    state.chatThinkingSelection,
                    capability: model.thinkingCapability,
                    supportsNone: model.supportsThinkingNone,
                )
                state.chatDefaultSettings.thinking = Self.persistedThinking(from: normalizedThinking)
                return Self.saveChatDefaultSettingsEffect(
                    settings: state.chatDefaultSettings,
                    client: chatDefaultSettingsClient,
                )

            case let .chatThinkingChanged(selection):
                guard let model = state.chatSelectedModel else { return .none }
                let normalized = AiThinkingSelectionPolicy.normalize(
                    selection,
                    capability: model.thinkingCapability,
                    supportsNone: model.supportsThinkingNone,
                )
                state.chatDefaultSettings.thinking = Self.persistedThinking(from: normalized)
                return Self.saveChatDefaultSettingsEffect(
                    settings: state.chatDefaultSettings,
                    client: chatDefaultSettingsClient,
                )

            case .chatResetTapped:
                state.chatDefaultSettings = .default
                state.chatModelRequestID = nil
                return Self.resetChatDefaultSettingsEffect(client: chatDefaultSettingsClient)

            case .row,
                 .delegate:
                return .none
            }
        }
        .forEach(\.rows, action: \.row) {
            AiConnectionRowReducer()
        }
    }
}

private extension AiSettingsFeature {
    static func applyBootstrapResults(
        _ results: [AIProviderBootstrapResult],
        to state: inout State,
    ) {
        for result in results {
            if let rowIdx = state.rows.index(id: result.provider) {
                state.rows[rowIdx].connectionState = result.connectionState
                state.rows[rowIdx].statusReason = result.statusReason
            }
        }
    }

    private static func bootstrapEffect(
        connectionsFileClient: AIConnectionsFileClient,
        verificationClient: AIProviderVerificationClient,
    ) -> Effect<Action> {
        AIProviderConnectionBootstrap.effect(
            connectionsFileClient: connectionsFileClient,
            verificationClient: verificationClient,
        ) { event in
            switch event {
            case let .completed(results):
                .bootstrapCompleted(results)
            case let .verificationCompleted(results):
                .bootstrapVerificationCompleted(results)
            case let .connectionsFileUpdated(file):
                .delegate(.connectionsFileUpdated(file))
            case .failed:
                .bootstrapFailed
            }
        }
        .cancellable(id: CancelID.bootstrap, cancelInFlight: true)
    }

    private static func refreshCollectionSearchModelsEffect(
        provider: AiProvider,
        providerModelListClient: AiProviderModelListClient,
        connectionsFileClient: AIConnectionsFileClient,
    ) -> Effect<Action> {
        .run { send in
            var modelsByProvider: [AiProvider: [AiProviderModel]] = [:]
            var failedProviders: [String] = []

            let file = try? await connectionsFileClient.load()
            guard let record = file?.providers[provider.rawValue],
                  let credential = record.credential
            else {
                await send(.collectionSearchModelsLoaded(modelsByProvider: [:], errorMessage: nil))
                return
            }

            do {
                let models = try await providerModelListClient.loadModels(provider, credential)
                let filtered = models.filter(CollectionSearchAISelectionPolicy.supportsQueryConversion)
                modelsByProvider[provider] = filtered
            } catch {
                failedProviders.append(provider.rawValue)
            }

            let errorMessage = failedProviders.isEmpty
                ? nil
                : "Failed to load models for: \(failedProviders.joined(separator: ", "))"
            await send(.collectionSearchModelsLoaded(modelsByProvider: modelsByProvider, errorMessage: errorMessage))
        }
        .cancellable(id: CancelID.collectionSearchModels, cancelInFlight: true)
    }

    private static func saveCollectionSearchSettingsEffect(
        settings: CollectionSearchAISettings,
        client: CollectionSearchAISettingsClient,
    ) -> Effect<Action> {
        .run { _ in
            client.save(settings)
        }
    }

    private static func refreshCollectionSearchModelsAfterBootstrapEffect(
        state: inout State,
        settingsClient: CollectionSearchAISettingsClient,
        providerModelListClient: AiProviderModelListClient,
        connectionsFileClient: AIConnectionsFileClient,
    ) -> Effect<Action> {
        let resetEffect = resetCollectionSearchProviderIfUnavailableInState(
            state: &state,
            client: settingsClient,
        )

        guard let provider = state.collectionSearchSelectedProvider,
              state.rows[id: provider]?.connectionState == .connected
        else { return resetEffect }

        return .merge(
            resetEffect,
            refreshCollectionSearchModelsEffect(
                provider: provider,
                providerModelListClient: providerModelListClient,
                connectionsFileClient: connectionsFileClient,
            ),
        )
    }

    private static func resetCollectionSearchProviderIfUnavailableInState(
        state: inout State,
        client: CollectionSearchAISettingsClient,
    ) -> Effect<Action> {
        guard let provider = state.collectionSearchSelectedProvider,
              let row = state.rows[id: provider],
              row.connectionState != .connected,
              row.connectionState != .checkingStatus
        else { return .none }

        return resetCollectionSearchProvider(state: &state, client: client)
    }

    private static func resetCollectionSearchProviderIfDisconnected(
        result: AiProviderConnectionResult,
        state: inout State,
        client: CollectionSearchAISettingsClient,
    ) -> Effect<Action> {
        guard result.state != .connected,
              state.collectionSearchSelectedProvider == result.provider
        else { return .none }

        state.collectionSearchModelsByProvider[result.provider] = nil
        return resetCollectionSearchProvider(state: &state, client: client)
    }

    private static func resetCollectionSearchProvider(
        state: inout State,
        client: CollectionSearchAISettingsClient,
    ) -> Effect<Action> {
        let previousSettings = state.collectionSearchSettings
        state.collectionSearchSettings = .default
        return previousSettings == state.collectionSearchSettings
            ? .none
            : saveCollectionSearchSettingsEffect(settings: state.collectionSearchSettings, client: client)
    }

    private static func normalizedCollectionSearchSettings(
        _ settings: CollectionSearchAISettings,
        modelsByProvider: [AiProvider: [AiProviderModel]],
    ) -> CollectionSearchAISettings {
        var normalized = settings

        switch normalized.provider {
        case .auto:
            normalized.model = .auto
            normalized.thinking = .providerDefault
            return normalized
        case let .specific(rawProvider):
            guard let provider = AiProvider(rawValue: rawProvider) else {
                normalized.provider = .auto
                normalized.model = .auto
                normalized.thinking = .providerDefault
                return normalized
            }

            guard let models = modelsByProvider[provider] else {
                return normalized
            }

            switch normalized.model {
            case .auto:
                normalized.thinking = .providerDefault
            case let .specific(modelProviderRaw, modelRaw):
                guard modelProviderRaw == provider.rawValue,
                      models.contains(where: { $0.rawModelID == modelRaw || $0.id.rawValue == modelRaw })
                else {
                    normalized.model = .auto
                    normalized.thinking = .providerDefault
                    return normalized
                }

                if let model = models.first(where: { $0.rawModelID == modelRaw || $0.id.rawValue == modelRaw }),
                   let thinking = CollectionSearchAISelectionPolicy.normalizeSelectedThinking(
                       normalized.thinkingSelection,
                       for: model,
                   )
                {
                    normalized.thinking = Self.thinkingPreference(from: thinking)
                } else {
                    normalized.thinking = .providerDefault
                }
            }

            if normalized.model == .auto {
                normalized.thinking = .providerDefault
            }

            return normalized
        }
    }
}

private extension CollectionSearchAISettings {
    var thinkingSelection: AiThinkingSelection? {
        switch thinking {
        case .providerDefault:
            nil
        case .none:
            .some(AiThinkingSelection.none)
        case let .effort(raw):
            AiThinkingEffort(rawValue: raw).map { .effort($0) }
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}

private extension AiSettingsFeature {
    static func thinkingPreference(from selection: AiThinkingSelection) -> CollectionSearchAIThinkingPreference {
        switch selection {
        case .none:
            CollectionSearchAIThinkingPreference.none
        case let .effort(effort):
            .effort(effort.rawValue)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }
}

private extension AiSettingsFeature {
    static func refreshChatModelsAfterBootstrapEffect(
        state: inout State,
        providerModelListClient: AiProviderModelListClient,
        connectionsFileClient: AIConnectionsFileClient,
        makeRequestID: () -> UUID,
    ) -> Effect<Action> {
        guard let provider = state.chatSelectedProvider,
              state.rows[id: provider]?.connectionState == .connected
        else {
            state.chatModelCatalogPhase = .idle
            state.chatModelRequestID = nil
            state.chatModelLoadError = nil
            return .none
        }

        let requestID = makeRequestID()
        state.chatModelsByProvider[provider] = nil
        state.chatModelCatalogPhase = .loading
        state.chatModelRequestID = requestID
        state.chatModelLoadError = nil
        return refreshChatModelsEffect(
            provider: provider,
            requestID: requestID,
            providerModelListClient: providerModelListClient,
            connectionsFileClient: connectionsFileClient,
        )
    }

    static func refreshChatModelsEffect(
        provider: AiProvider,
        requestID: UUID,
        providerModelListClient: AiProviderModelListClient,
        connectionsFileClient: AIConnectionsFileClient,
    ) -> Effect<Action> {
        .run { send in
            let failureMessage = "Failed to load chat models for \(provider.rawValue)."
            do {
                let file = try await connectionsFileClient.load()
                try Task.checkCancellation()
                guard let credential = file.providers[provider.rawValue]?.credential else {
                    await send(.chatModelsFailed(
                        provider: provider,
                        requestID: requestID,
                        message: failureMessage,
                    ))
                    return
                }
                let models = try await providerModelListClient.loadModels(provider, credential)
                try Task.checkCancellation()
                await send(.chatModelsLoaded(provider: provider, requestID: requestID, models: models))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.chatModelsFailed(
                    provider: provider,
                    requestID: requestID,
                    message: failureMessage,
                ))
            }
        }
        .cancellable(id: CancelID.chatModels, cancelInFlight: true)
    }

    static func saveChatDefaultSettingsEffect(
        settings: AiChatDefaultSettings,
        client: AiChatDefaultSettingsClient,
    ) -> Effect<Action> {
        .run { _ in
            client.save(settings)
        }
    }

    static func resetChatDefaultSettingsEffect(
        client: AiChatDefaultSettingsClient,
    ) -> Effect<Action> {
        .run { _ in
            client.reset()
        }
    }

    static func invalidateChatCatalogIfDisconnected(
        result: AiProviderConnectionResult,
        state: inout State,
    ) {
        guard result.state != .connected,
              state.chatSelectedProvider == result.provider
        else { return }

        state.chatModelsByProvider[result.provider] = nil
        state.chatModelCatalogPhase = .idle
        state.chatModelRequestID = nil
        state.chatModelLoadError = nil
    }

    static func persistedThinking(from selection: AiThinkingSelection?) -> PersistedAIThinkingSelection {
        guard let selection else { return .providerDefault }
        switch selection {
        case .none:
            return PersistedAIThinkingSelection.none
        case let .effort(effort):
            return .effort(effort.rawValue)
        case let .tokenBudget(value):
            return .tokenBudget(value)
        }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

struct AiChatModelListLoadRequest: Equatable {
    var requestID: UUID
    var provider: AiProvider
    var credential: StoredCredentialPayload?
}

struct AiChatModelListLoadBatch: Equatable {
    var requestID: UUID
    var requests: [AiChatModelListLoadRequest]
}

extension AiChatFeature {
    func handleSelectedModelChanged(_ handle: AiModelHandle?, state: inout State) -> Effect<Action> {
        let resolvedHandle = state.normalizedSelectionHandle(handle)
        guard state.selectedModelHandle != resolvedHandle else { return .none }
        state.markPreparedTransientSessionAsTouched()
        state.selectedModelHandle = resolvedHandle
        state.unavailableSelectedModelHandle = nil
        normalizeSelectionIfNeeded(&state)
        clearRetryBlockingFailureIfNeeded(&state)
        return .none
    }

    func handleSelectedThinkingChanged(
        _ selectedThinking: AiThinkingSelection?,
        state: inout State,
    ) -> Effect<Action> {
        guard state.selectedThinking != selectedThinking else { return .none }
        state.markPreparedTransientSessionAsTouched()
        state.selectedThinking = selectedThinking
        normalizeSelectionIfNeeded(&state)
        clearRetryBlockingFailureIfNeeded(&state)
        return .none
    }

    func makeModelListLoadBatch(from file: AIConnectionsFile, state: State) -> AiChatModelListLoadBatch? {
        let preferredProviders = [
            state.selectedModelHandle?.provider,
            state.unavailableSelectedModelHandle?.provider,
            state.lockedModelHandle?.provider,
            state.modelListProvider,
            file.lastUsedProviderId,
        ].compactMap(\.self)

        let connectedRecords = file.providers.values.filter { $0.snapshot.lastKnownStatus == .connected }
        guard !connectedRecords.isEmpty else { return nil }

        let connectedRecordsByProvider = Dictionary(uniqueKeysWithValues: connectedRecords.map { ($0.providerId, $0) })
        var orderedProviders: [AiProvider] = []

        for provider in preferredProviders
            where connectedRecordsByProvider[provider] != nil && !orderedProviders.contains(provider)
        {
            orderedProviders.append(provider)
        }

        for provider in connectedRecordsByProvider.keys.sorted(by: { $0.rawValue < $1.rawValue })
            where !orderedProviders.contains(provider)
        {
            orderedProviders.append(provider)
        }

        guard !orderedProviders.isEmpty else { return nil }

        let requestID = uuid()
        return AiChatModelListLoadBatch(
            requestID: requestID,
            requests: orderedProviders.compactMap { provider in
                guard let record = connectedRecordsByProvider[provider] else { return nil }
                return AiChatModelListLoadRequest(
                    requestID: requestID,
                    provider: provider,
                    credential: record.credential,
                )
            },
        )
    }

    func loadModelList(
        requestID: UUID,
        provider: AiProvider,
        credential: StoredCredentialPayload?,
    ) -> Effect<Action> {
        .run { [aiProviderModelListClient] send in
            do {
                let models = try await aiProviderModelListClient.loadModels(provider, credential)
                await send(.modelListLoaded(requestID: requestID, provider: provider, models: models))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.modelListLoadFailed(
                    requestID: requestID,
                    provider: provider,
                    failure: Self.makeModelListFailure(provider: provider, error: error),
                ))
            }
        }
        .cancellable(id: CancelID.modelList)
    }

    func applyModelListState(_ modelListState: AiChatModelListState, to state: inout State) {
        state.modelListState = modelListState

        switch modelListState {
        case let .loaded(models):
            state.catalogRows = State.makeCatalogRows(for: models, preserving: state.catalogRows)
            if let currentSelection = state.selectedModelHandle,
               let resolvedSelection = state.normalizedSelectionHandle(currentSelection, in: models)
            {
                state.selectedModelHandle = resolvedSelection
                state.unavailableSelectedModelHandle = nil
            } else if let currentSelection = state.selectedModelHandle {
                applyMissingSelectedModel(currentSelection, to: &state)
            }

        case .empty:
            if let previousSelection = state.selectedModelHandle {
                applyMissingSelectedModel(previousSelection, to: &state)
            }
            state.catalogRows = []

        case .idle, .loading, .failed:
            if case .idle = modelListState {
                state.availableModelsByProvider = [:]
            }
            if case .failed = modelListState {
                state.availableModelsByProvider = [:]
            }
        }

        normalizeSelectionIfNeeded(&state)
        clearRetryBlockingFailureIfNeeded(&state)
    }

    func finalizeModelListBatchIfNeeded(_ state: inout State) {
        guard state.modelListPendingProviders.isEmpty else { return }

        let loadedModelsByProvider = state.modelListProviderOrder
            .reduce(into: [AiProvider: [AiProviderModel]]()) { partialResult, provider in
                partialResult[provider] = state.modelListLoadedModelsByProvider[provider] ?? []
            }
        let mergedModels = state.modelListProviderOrder.flatMap { provider in
            loadedModelsByProvider[provider] ?? []
        }
        let firstFailure = state.modelListProviderOrder
            .first { provider in
                state.modelListFailedProviders[provider] != nil
            }
            .flatMap { provider in
                state.modelListFailedProviders[provider]
            }

        let nextModelListState: AiChatModelListState = if !mergedModels.isEmpty {
            .loaded(mergedModels)
        } else if let failure = firstFailure {
            .failed(failure)
        } else {
            .empty
        }

        state.availableModelsByProvider = loadedModelsByProvider
        state.modelListRequestID = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        applyModelListState(nextModelListState, to: &state)
    }

    func clearModelListTracking(_ state: inout State) {
        state.modelListRequestID = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
    }

    static func makeModelListFailure(provider: AiProvider, error: Error) -> AiModelListFailure {
        let providerDisplayName = ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue

        if let error = error as? AiProviderModelListError {
            let message = switch error {
            case .missingCredential:
                "\(providerDisplayName) credential is missing."
            case .invalidCredential:
                "\(providerDisplayName) credential is invalid."
            case .unsupportedProvider:
                "\(providerDisplayName) model listing is unavailable."
            case .invalidResponse:
                "\(providerDisplayName) returned an invalid model list response."
            case let .httpError(_, statusCode, _):
                "\(providerDisplayName) model list request failed (\(statusCode))."
            case .networkError:
                "\(providerDisplayName) model list request failed due to a network error."
            }
            let reason: AiModelListFailureReason = if case .unsupportedProvider = error {
                .unsupportedProvider
            } else {
                .generic
            }
            return AiModelListFailure(message: message, reason: reason)
        }

        return AiModelListFailure(message: "Unable to load models for \(providerDisplayName).")
    }

    func handleProviderConnectionsUpdated(file: AIConnectionsFile, state: inout State) -> Effect<Action> {
        guard let loadBatch = makeModelListLoadBatch(from: file, state: state) else {
            state.providerConnectionSnapshot = .known([])
            state.availableModelsByProvider = [:]
            clearModelListTracking(&state)
            state.modelListProvider = nil
            applyModelListState(.empty, to: &state)
            return .cancel(id: CancelID.modelList)
        }

        let connectedProviders = loadBatch.requests.map(\.provider)
        state.providerConnectionSnapshot = .known(connectedProviders)
        state.availableModelsByProvider = [:]
        state.modelListRequestID = loadBatch.requestID
        state.modelListProvider = loadBatch.requests.first?.provider
        state.modelListProviderOrder = connectedProviders
        state.modelListPendingProviders = Set(connectedProviders)
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
        applyModelListState(.loading, to: &state)

        return .concatenate(
            .cancel(id: CancelID.modelList),
            .merge(loadBatch.requests.map { loadRequest in
                .send(.modelListLoading(
                    requestID: loadRequest.requestID,
                    provider: loadRequest.provider,
                    credential: loadRequest.credential,
                ))
            }),
        )
    }
}

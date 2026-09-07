import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection

@Reducer
struct AiProviderSetupFeature {
    typealias State = AiProviderSetupState
    typealias Action = AiProviderSetupAction

    @Dependency(\.aiConnectionsFileClient)
    var connectionsFileClient
    @Dependency(\.aiProviderVerificationClient)
    var verificationClient
    @Dependency(\.onboardingProductMetricsClient)
    var metricsClient

    private enum CancelID: Hashable {
        case bootstrap
    }

    var body: some Reducer<State, Action> {
        CombineReducers {
            EmptyReducer()
                .forEach(\.rows, action: \.row) {
                    AiConnectionRowReducer()
                }

            Reduce { state, action in
                switch action {
                case .onAppear:
                    guard !state.didBootstrap else { return .none }
                    state.didBootstrap = true
                    state.bootstrapPhase = .loading
                    state.loadError = nil
                    return Self.bootstrapEffect(
                        connectionsFileClient: connectionsFileClient,
                        verificationClient: verificationClient,
                    )

                case .retryBootstrapTapped:
                    state.bootstrapPhase = .loading
                    state.loadError = nil
                    return Self.bootstrapEffect(
                        connectionsFileClient: connectionsFileClient,
                        verificationClient: verificationClient,
                    )

                case .setUpLaterTapped:
                    let providers = Array(state.pendingConnectionOperationIDs.keys)
                    state.pendingConnectionOperationIDs.removeAll()
                    var effects: [Effect<Action>] = providers.map { provider in
                        .send(.row(.element(id: provider, action: .cancelButtonTapped)))
                    }
                    effects.append(.cancel(id: CancelID.bootstrap))
                    return .merge(effects)

                case let .bootstrapCompleted(results):
                    Self.applyBootstrapResults(results, to: &state)
                    state.bootstrapPhase = .loaded
                    state.loadError = nil
                    state.refreshStatus()
                    return .none

                case let .bootstrapVerificationCompleted(results):
                    Self.applyBootstrapResults(results, to: &state)
                    state.bootstrapPhase = .loaded
                    state.loadError = nil
                    state.refreshStatus()
                    return .none

                case .bootstrapFailed:
                    state.bootstrapPhase = .failed
                    state.loadError = "Failed to load AI connections."
                    state.refreshStatus()
                    return .none

                case let .row(.element(id: provider, action: rowAction)):
                    Self.recordTerminalMetric(
                        for: rowAction,
                        provider: provider,
                        state: &state,
                        metricsClient: metricsClient,
                    )
                    state.refreshStatus()
                    if Self.shouldReloadLatestStatus(after: rowAction) {
                        return Self.bootstrapEffect(
                            connectionsFileClient: connectionsFileClient,
                            verificationClient: verificationClient,
                        )
                    }
                    return .none

                case .row:
                    state.refreshStatus()
                    return .none
                }
            }
        }
    }

    private static func applyBootstrapResults(
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
            case .connectionsFileUpdated:
                nil
            case .failed:
                .bootstrapFailed
            }
        }
        .cancellable(id: CancelID.bootstrap, cancelInFlight: true)
    }

    private static func shouldReloadLatestStatus(after action: AiConnectionRowAction) -> Bool {
        switch action {
        case .connectionResponse:
            true
        case let .disconnectResponse(result):
            result.state == .notVerified
        default:
            false
        }
    }

    private static func recordTerminalMetric(
        for action: AiConnectionRowAction,
        provider: AiProvider,
        state: inout State,
        metricsClient: OnboardingProductMetricsClient,
    ) {
        let result: OnboardingProductMetric.AIProviderResult?
        switch action {
        case let .connectionResponse(response):
            result = response.state == .connected ? .success : .failure
        case .verificationResponse(.invalid),
             .verificationResponse(.unsupportedProvider),
             .verificationResponse(.networkError):
            result = .failure
        case .browserLoginFailed(.cancelled), .deviceAuthFailed(.cancelled), .cancelButtonTapped:
            state.pendingConnectionOperationIDs.removeValue(forKey: provider)
            return
        case .browserLoginFailed, .deviceAuthFailed, .verificationFailed:
            result = .failure
        default:
            guard state.pendingConnectionOperationIDs[provider] == nil else { return }
            switch action {
            case .connectButtonTapped, .submitAPIKey, .retryButtonTapped:
                state.choice = .none
                state.pendingConnectionOperationIDs[provider] = UUID()
            default:
                break
            }
            return
        }

        guard let result,
              let operationID = state.pendingConnectionOperationIDs.removeValue(forKey: provider)
        else { return }
        metricsClient.record(.aiProviderWithKind(
            operationID: operationID,
            provider: .init(provider: provider),
            result: result,
        ))
    }
}

@CasePathable
enum AiProviderSetupAction: CasePathable, Equatable {
    case onAppear
    case bootstrapCompleted([AIProviderBootstrapResult])
    case bootstrapVerificationCompleted([AIProviderBootstrapResult])
    case bootstrapFailed
    case retryBootstrapTapped
    case setUpLaterTapped
    case row(IdentifiedActionOf<AiConnectionRowReducer>)
}

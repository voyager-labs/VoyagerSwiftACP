import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection

@Reducer
public struct AiSettingsFeature {
    public typealias State = AiSettingsState
    public typealias Action = AiSettingsAction

    @Dependency(\.aiConnectionsFileClient)
    var connectionsFileClient
    @Dependency(\.aiProviderVerificationClient)
    var verificationClient

    public init() {}

    private enum CancelID: Hashable {
        case bootstrap
    }

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.didBootstrap else { return .none }
                state.didBootstrap = true
                state.bootstrapPhase = .loading
                return Self.bootstrapEffect(
                    connectionsFileClient: connectionsFileClient,
                    verificationClient: verificationClient,
                )

            case let .bootstrapCompleted(results):
                Self.applyBootstrapResults(results, to: &state)
                state.bootstrapPhase = .loaded
                return .none

            case let .bootstrapVerificationCompleted(results):
                Self.applyBootstrapResults(results, to: &state)
                state.bootstrapPhase = .loaded
                return .none

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
                return .send(.delegate(.connectionsFileUpdated(result.updatedFile)))

            case .row,
                 .delegate:
                return .none
            }
        }
        .forEach(\.rows, action: \.row) {
            AiConnectionRowReducer()
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
            case let .connectionsFileUpdated(file):
                .delegate(.connectionsFileUpdated(file))
            case .failed:
                .bootstrapFailed
            }
        }
        .cancellable(id: CancelID.bootstrap, cancelInFlight: true)
    }
}

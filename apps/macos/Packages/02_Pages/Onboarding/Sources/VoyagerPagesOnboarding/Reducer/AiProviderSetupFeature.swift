import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
struct AiProviderSetupFeature {
    typealias State = AiProviderSetupState
    typealias Action = AiProviderSetupAction

    @Dependency(\.aiConnectionsFileClient)
    var connectionsFileClient
    @Dependency(\.aiProviderVerificationClient)
    var verificationClient

    var body: some Reducer<State, Action> {
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
                state.choice = .setUpLater
                state.loadError = nil
                state.refreshStatus()
                return .none

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

            case let .row(.element(id: _, action: rowAction)):
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
        .forEach(\.rows, action: \.row) {
            AiProviderSetupRowFeature()
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
        .run { send in
            let file: AIConnectionsFile
            do {
                file = try await connectionsFileClient.load()
            } catch {
                await send(.bootstrapFailed)
                return
            }

            await send(.bootstrapCompleted(AIProviderConnectionBootstrap.initialResults(from: file)))

            let verificationResults = await Self.bootstrapVerificationResults(
                from: file,
                verificationClient: verificationClient,
            )
            if !verificationResults.isEmpty {
                await send(.bootstrapVerificationCompleted(verificationResults))
                await Self.persistBootstrapVerificationResults(
                    verificationResults,
                    file: file,
                    connectionsFileClient: connectionsFileClient,
                )
            }
        }
    }

    private static func shouldReloadLatestStatus(after action: AiProviderSetupRowAction) -> Bool {
        switch action {
        case .cancelButtonTapped,
             .verificationFailed,
             .browserLoginFailed,
             .deviceAuthFailed,
             .connectionResponse:
            true
        default:
            false
        }
    }

    private static func bootstrapVerificationResults(
        from file: AIConnectionsFile,
        verificationClient: AIProviderVerificationClient,
    ) async -> [AIProviderBootstrapResult] {
        var results: [AIProviderBootstrapResult] = []

        for descriptor in ProviderDescriptor.v1Catalog {
            guard let record = file.providers[descriptor.provider.rawValue],
                  AIProviderConnectionBootstrap.shouldVerify(snapshotState: record.snapshot.lastKnownStatus),
                  let credential = record.credential
            else { continue }

            let verification = await verificationClient.verify(descriptor.provider, credential)
            results.append(
                AIProviderConnectionBootstrap.verifiedResult(
                    for: descriptor.provider,
                    verification: verification,
                ),
            )
        }

        return results
    }

    private static func persistBootstrapVerificationResults(
        _ results: [AIProviderBootstrapResult],
        file: AIConnectionsFile,
        connectionsFileClient: AIConnectionsFileClient,
    ) async {
        guard let latestFile = try? await connectionsFileClient.load(),
              let updatedFile = AIProviderConnectionBootstrap.updatedConnectionsFile(
                  verificationSourceFile: file,
                  latestFile: latestFile,
                  applying: results,
              )
        else { return }

        let mutationResult = await (try? connectionsFileClient.save(updatedFile))
        switch mutationResult {
        case let .success(savedFile), let .partialSuccess(savedFile, _):
            _ = savedFile
        // The onboarding step reads the latest state through its own bootstrap cycle.
        case .fileSystemError, nil:
            break
        }
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
    case row(IdentifiedActionOf<AiProviderSetupRowFeature>)
}

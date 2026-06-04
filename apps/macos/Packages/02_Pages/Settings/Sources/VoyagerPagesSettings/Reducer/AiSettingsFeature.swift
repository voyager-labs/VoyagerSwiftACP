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
                    send: send,
                )
            }
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
        send: Send<Action>,
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
            await send(.delegate(.connectionsFileUpdated(savedFile)))
        case .fileSystemError, nil:
            break
        }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiSettingsFeature {
    public typealias State = AiSettingsState
    public typealias Action = AiSettingsAction

    private static let checkingStatusRawValue = "checkingStatus"

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
                    verificationClient: verificationClient
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
                    verificationClient: verificationClient
                )

            case let .row(.element(id: _, action: ._connectionResponse(result))),
                 let .row(.element(id: _, action: ._disconnectResponse(result))):
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

    /// Maps persisted provider records to the initial restore state.
    /// Stored credentials enter `checkingStatus` unless the row is a stale transient or disconnect state.
    package static func bootstrapInitialResults(from file: AIConnectionsFile) -> [AiProviderBootstrapResult] {
        ProviderDescriptor.v1Catalog.map { descriptor in
            let record = file.providers[descriptor.provider.rawValue]
            return bootstrapInitialResult(for: descriptor.provider, record: record)
        }
    }

    private static func applyBootstrapResults(
        _ results: [AiProviderBootstrapResult],
        to state: inout State
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
        verificationClient: AIProviderVerificationClient
    ) -> Effect<Action> {
        .run { send in
            let file: AIConnectionsFile
            do {
                file = try await connectionsFileClient.load()
            } catch {
                await send(.bootstrapFailed)
                return
            }
            await send(.bootstrapCompleted(Self.bootstrapInitialResults(from: file)))

            let verificationResults = await Self.bootstrapVerificationResults(
                from: file,
                verificationClient: verificationClient
            )
            if !verificationResults.isEmpty {
                await send(.bootstrapVerificationCompleted(verificationResults))
                await Self.persistBootstrapVerificationResults(
                    verificationResults,
                    file: file,
                    connectionsFileClient: connectionsFileClient,
                    send: send
                )
            }
        }
    }

    package static func bootstrapInitialResult(
        for provider: AiProvider,
        record: ProviderRecordFile?
    ) -> AiProviderBootstrapResult {
        guard let record else {
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none
            )
        }

        guard record.credential != nil else {
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .missingCredential
            )
        }

        switch record.snapshot.lastKnownStatus {
        case .disconnecting, .disconnected:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .disconnected,
                statusReason: .none
            )
        case .connectInProgress:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none
            )
        default:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .init(rawValue: Self.checkingStatusRawValue) ?? .notVerified,
                statusReason: .none
            )
        }
    }

    package static func bootstrapVerificationResults(
        from file: AIConnectionsFile,
        verificationClient: AIProviderVerificationClient
    ) async -> [AiProviderBootstrapResult] {
        var results: [AiProviderBootstrapResult] = []

        for descriptor in ProviderDescriptor.v1Catalog {
            guard let record = file.providers[descriptor.provider.rawValue],
                  shouldVerify(snapshotState: record.snapshot.lastKnownStatus),
                  let credential = record.credential
            else { continue }

            let verification = await verificationClient.verify(descriptor.provider, credential)
            results.append(
                bootstrapVerifiedResult(
                    for: descriptor.provider,
                    verification: verification
                )
            )
        }

        return results
    }

    private static func persistBootstrapVerificationResults(
        _ results: [AiProviderBootstrapResult],
        file: AIConnectionsFile,
        connectionsFileClient: AIConnectionsFileClient,
        send: Send<Action>
    ) async {
        guard let updatedFile = bootstrapUpdatedConnectionsFile(file, applying: results) else { return }

        let mutationResult = await (try? connectionsFileClient.save(updatedFile))
        switch mutationResult {
        case let .success(savedFile), let .partialSuccess(savedFile, _):
            await send(.delegate(.connectionsFileUpdated(savedFile)))
        case .fileSystemError, nil:
            break
        }
    }

    package static func bootstrapUpdatedConnectionsFile(
        _ file: AIConnectionsFile,
        applying results: [AiProviderBootstrapResult]
    ) -> AIConnectionsFile? {
        var providers = file.providers
        var didUpdate = false

        for result in results {
            guard var record = providers[result.provider.rawValue],
                  record.credential != nil
            else { continue }

            let lastErrorCode: ProviderStatusReason = result.connectionState == .connected ? .none : result.statusReason
            guard record.snapshot.lastKnownStatus != result.connectionState
                || record.snapshot.lastErrorCode != lastErrorCode
            else { continue }

            let snapshot = ProviderSnapshotFile(
                lastKnownStatus: result.connectionState,
                lastVerifiedAtMs: result.connectionState == .connected ? file.updatedAtMs : nil,
                lastErrorCode: lastErrorCode
            )

            record = ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: record.credential,
                snapshot: snapshot,
                provenance: record.provenance
            )
            providers[result.provider.rawValue] = record
            didUpdate = true
        }

        guard didUpdate else { return nil }
        return AIConnectionsFile(
            schemaVersion: file.schemaVersion,
            updatedAtMs: file.updatedAtMs,
            lastUsedProviderId: file.lastUsedProviderId,
            lastUsedAtMs: file.lastUsedAtMs,
            providers: providers
        )
    }

    private static func shouldVerify(snapshotState: ProviderConnectionState) -> Bool {
        guard snapshotState.rawValue != checkingStatusRawValue else { return true }
        switch snapshotState {
        case .connectInProgress, .disconnecting, .disconnected:
            return false
        case .notVerified, .connected, .connectionFailed, .unavailable:
            return true
        default:
            return true
        }
    }

    private static func bootstrapVerifiedResult(
        for provider: AiProvider,
        verification: AiProviderVerificationResult
    ) -> AiProviderBootstrapResult {
        switch verification {
        case .valid:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .connected,
                statusReason: .none
            )
        case let .invalid(reason):
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .connectionFailed,
                statusReason: reason
            )
        case .networkError:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .connectionFailed,
                statusReason: .networkUnavailable
            )
        case .unsupportedProvider:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .unavailable,
                statusReason: .providerUnsupportedInBuild
            )
        }
    }
}

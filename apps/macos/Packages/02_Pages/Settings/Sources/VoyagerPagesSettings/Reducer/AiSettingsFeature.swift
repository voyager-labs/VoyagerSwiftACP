import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

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
                return .run { [connectionsFileClient] send in
                    let file: AIConnectionsFile
                    do {
                        file = try await connectionsFileClient.load()
                    } catch {
                        file = AIConnectionsFile.empty()
                    }
                    let results = Self.bootstrapResults(from: file)
                    await send(.bootstrapCompleted(results))
                }

            case let .bootstrapCompleted(results):
                for result in results {
                    if let rowIdx = state.rows.index(id: result.provider) {
                        state.rows[rowIdx].connectionState = result.connectionState
                        state.rows[rowIdx].statusReason = result.statusReason
                    }
                }
                return .none

            case .row:
                return .none
            }
        }
        forEach(\.rows, action: \.row) {
            AiConnectionRowReducer()
        }
    }

    /// Maps persisted provider records to bootstrap results.
    /// Providers with no stored record → `notVerified`.
    /// Providers with stored credential + valid snapshot → `connected` (deferred re-verification).
    /// Providers with stored credential + failed snapshot → `connectionFailed`.
    /// Providers with corrupted/invalid record → `connectionFailed`.
    package static func bootstrapResults(from file: AIConnectionsFile) -> [AiProviderBootstrapResult] {
        ProviderDescriptor.v1Catalog.map { descriptor in
            let record = file.providers[descriptor.provider.rawValue]
            return bootstrapResult(for: descriptor.provider, record: record)
        }
    }

    package static func bootstrapResult(
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

        let snapshotState = record.snapshot.lastKnownStatus
        switch snapshotState {
        case .connected:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .connected,
                statusReason: .none
            )
        case .connectionFailed:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .connectionFailed,
                statusReason: record.snapshot.lastErrorCode
            )
        case .notVerified:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .notVerified,
                statusReason: .none
            )
        case .disconnecting:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .disconnected,
                statusReason: .none
            )
        case .disconnected:
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
        case .unavailable:
            return AiProviderBootstrapResult(
                provider: provider,
                connectionState: .unavailable,
                statusReason: record.snapshot.lastErrorCode
            )
        }
    }
}

import ComposableArchitecture
import VoyagerEntitiesAi

@CasePathable
public enum AiSettingsAction: CasePathable, Sendable {
    case onAppear
    case bootstrapCompleted([AiProviderBootstrapResult])
    case bootstrapVerificationCompleted([AiProviderBootstrapResult])
    case bootstrapFailed
    case retryBootstrapTapped
    case row(IdentifiedActionOf<AiConnectionRowReducer>)
}

/// Result of bootstrapping a single provider from persisted credentials.
public struct AiProviderBootstrapResult: Equatable, Sendable {
    public let provider: AiProvider
    public let connectionState: ProviderConnectionState
    public let statusReason: ProviderStatusReason

    public init(
        provider: AiProvider,
        connectionState: ProviderConnectionState,
        statusReason: ProviderStatusReason = .none
    ) {
        self.provider = provider
        self.connectionState = connectionState
        self.statusReason = statusReason
    }
}

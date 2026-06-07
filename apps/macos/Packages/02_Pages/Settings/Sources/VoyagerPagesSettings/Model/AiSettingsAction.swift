import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection

@CasePathable
public enum AiSettingsAction: CasePathable, Equatable, Sendable {
    case delegate(Delegate)

    case onAppear
    case bootstrapCompleted([AIProviderBootstrapResult])
    case bootstrapVerificationCompleted([AIProviderBootstrapResult])
    case bootstrapFailed
    case retryBootstrapTapped
    case row(IdentifiedActionOf<AiConnectionRowReducer>)

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case connectionsFileUpdated(AIConnectionsFile)
    }
}

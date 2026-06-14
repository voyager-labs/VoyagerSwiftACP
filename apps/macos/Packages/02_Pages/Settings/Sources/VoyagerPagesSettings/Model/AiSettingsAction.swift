import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
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

    case collectionSearchSettingsLoaded(CollectionSearchAISettings)
    case collectionSearchModelsLoaded(modelsByProvider: [AiProvider: [AiProviderModel]], errorMessage: String?)
    case collectionSearchProviderChanged(CollectionSearchAIProviderPreference)
    case collectionSearchModelChanged(CollectionSearchAIModelPreference)
    case collectionSearchThinkingChanged(CollectionSearchAIThinkingPreference)
    case collectionSearchResetTapped

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case connectionsFileUpdated(AIConnectionsFile)
    }
}

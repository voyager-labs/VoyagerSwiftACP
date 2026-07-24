import ComposableArchitecture
import Foundation
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

    case chatModelsLoaded(provider: AiProvider, requestID: UUID, models: [AiProviderModel])
    case chatModelsFailed(provider: AiProvider, requestID: UUID, message: String)
    case chatProviderChanged(PersistedAIProviderSelection)
    case chatModelChanged(PersistedAIModelSelection)
    case chatThinkingChanged(AiThinkingSelection?)
    case chatResetTapped

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case connectionsFileUpdated(AIConnectionsFile)
    }
}

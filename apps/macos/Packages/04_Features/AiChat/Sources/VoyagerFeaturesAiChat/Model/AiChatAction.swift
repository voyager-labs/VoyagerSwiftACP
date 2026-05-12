import ComposableArchitecture
import VoyagerEntitiesAi

@CasePathable
public enum AiChatAction: CasePathable, Equatable, Sendable {
    case onAppear
    case setup(AiChatSetupState)
    case availableModelsUpdated(catalogRows: [AiModelCatalogRow], selectedModelHandle: AiModelHandle?)
    case selectedModelChanged(AiModelHandle?)
    case draftTextChanged(String)
    case openSettingsTapped
    case submitTapped
    case regenerateTapped
    case cancelTapped
    case resetTapped
    case restoreOutcome(
        requestedSessionID: AiChatSessionID,
        AiChatSessionRestoreResult,
        restoreFailure: AiChatSessionRestoreFailure?
    )
    case executionEvent(AiChatEvent)
    case persistenceFailed(AiChatRequestLock, AiChatExecutionFailure)
}

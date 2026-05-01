import ComposableArchitecture
import VoyagerEntitiesAi

@CasePathable
public enum AiChatAction: CasePathable, Equatable, Sendable {
    case onAppear
    case setup(AiChatSetupState)
    case selectedModelChanged(AiModelHandle?)
    case draftTextChanged(String)
    case submitTapped
    case regenerateTapped
    case cancelTapped
    case resetTapped
    case restoreOutcome(AiChatSessionRestoreResult, restoreFailure: AiChatSessionRestoreFailure?)
    case executionEvent(AiChatEvent)
    case persistenceFailed(AiChatRequestLock, AiChatExecutionFailure)
}

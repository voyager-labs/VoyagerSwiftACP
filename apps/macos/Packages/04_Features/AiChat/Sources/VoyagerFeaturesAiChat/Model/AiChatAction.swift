import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@CasePathable
public enum AiChatAction: CasePathable, Equatable, Sendable {
    case delegate(Delegate)
    case onAppear
    case sessionsAppeared
    case newChatTapped
    case sessionRowTapped(AiChatSessionID)
    case deleteSessionTapped(AiChatSessionID)
    case backToSessionsTapped
    case sessionSearchQueryChanged(String)
    case sessionListLoaded([AiChatSessionSummary])
    case sessionListFailed(String)
    case sessionDeleteSucceeded(AiChatSessionID)
    case sessionDeleteFailed(AiChatSessionID, String)
    case newChatCreated(AiChatSessionSnapshot)
    case newChatFailed(String)
    case setup(AiChatSetupState)
    case providerConnectionsUpdated(AIConnectionsFile)
    case modelListLoading(requestID: UUID, provider: AiProvider, credential: StoredCredentialPayload?)
    case modelListLoaded(requestID: UUID, provider: AiProvider, models: [AiProviderModel])
    case modelListLoadFailed(requestID: UUID, provider: AiProvider, failure: AiModelListFailure)
    case modelSelectorTapped
    case modelSelectorDismissed
    case selectedModelChanged(AiModelHandle?)
    case selectedThinkingChanged(AiThinkingSelection?)
    case currentContextChanged(AiChatCurrentContextSnapshot)
    case draftTextChanged(String)
    case attachmentPickerTapped
    case attachmentPickerSelection([URL])
    case attachmentDropSelection([URL])
    case removeAddedAttachment(AiChatAttachmentID)
    case openSettingsTapped
    case errorRecoveryTapped
    case rebindContextTapped
    case startNewChatFromRebindTapped
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
    case persistenceRecoverySucceeded(AiChatRequestLock)
    case persistenceRecoveryRetryFailed(AiChatRequestLock, AiChatExecutionFailure)

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case openAISettings
        case requestAttachmentPicker
        case clearCurrentContextSelection
    }
}

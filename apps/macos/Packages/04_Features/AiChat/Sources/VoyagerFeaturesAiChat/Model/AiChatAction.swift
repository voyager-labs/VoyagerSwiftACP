import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public struct AiChatAttachmentDropProvider: Equatable, @unchecked Sendable {
    public let id: UUID
    public let provider: NSItemProvider

    public init(id: UUID, provider: NSItemProvider) {
        self.id = id
        self.provider = provider
    }

    public init(provider: NSItemProvider) {
        self.init(id: UUID(), provider: provider)
    }

    public static func == (lhs: AiChatAttachmentDropProvider, rhs: AiChatAttachmentDropProvider) -> Bool {
        lhs.id == rhs.id
    }
}

public enum AiChatFolderContextTarget: Codable, Equatable, Sendable {
    case currentContext
    case attachment(AiChatAttachmentID)
}

@CasePathable
public enum AiChatAction: CasePathable, Equatable, Sendable {
    case delegate(Delegate)
    case onAppear
    case sessionsAppeared
    case newChatTapped
    case newChatTappedWithSeed(AiChatNewChatSelectionSeed)
    case newChatTappedIfCurrent(
        provenance: AiChatNewChatPreparationProvenance,
        seed: AiChatNewChatSelectionSeed?,
    )
    case prepareUnpersistedNewChat
    case prepareUnpersistedNewChatWithSeed(AiChatNewChatSelectionSeed)
    case prepareTransientNewChat(
        sessionID: AiChatSessionID,
        seed: AiChatNewChatSelectionSeed?,
    )
    case prepareTransientNewChatIfCurrent(
        sessionID: AiChatSessionID,
        provenance: AiChatNewChatPreparationProvenance,
        seed: AiChatNewChatSelectionSeed?,
    )
    case prepareUnpersistedNewChatWithContext(AiChatCurrentContextSnapshot)
    case prepareTransientNewChatWithContext(
        AiChatCurrentContextSnapshot,
        AiChatNewChatSelectionSeed,
    )
    case prepareUnpersistedNewChatWithContextIfCurrent(
        AiChatCurrentContextSnapshot,
        provenance: AiChatNewChatPreparationProvenance,
        seed: AiChatNewChatSelectionSeed?,
    )
    case showSessionsTapped
    case showSessionsForChat(AiChatSessionID)
    case returnToChatTapped
    case routeToChatSession(AiChatSessionID)
    case sessionRowTapped(AiChatSessionID)
    case deleteSessionTapped(AiChatSessionID)
    case renameSessionTapped(AiChatSessionID)
    case renameSessionTitleChanged(String)
    case renameSessionConfirmed
    case renameSessionCancelled
    case backToSessionsTapped
    case sessionSearchQueryChanged(String)
    case sessionListLoaded([AiChatSessionSummary])
    case sessionListFailed(String)
    case sessionDeleteSucceeded(AiChatSessionID)
    case sessionDeleteFailed(AiChatSessionID, String)
    case sessionRenameSucceeded(AiChatSessionSummary, customTitle: String?)
    case sessionRenameFailed(AiChatSessionID, String)
    case sessionSnapshotUpdated(
        AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
    )
    case sessionSnapshotUpdateFailed(requestID: AiChatRequestID, runID: AiChatRunID)
    case sessionSnapshotSaved(
        AiChatSessionSummary,
        snapshot: AiChatSessionSnapshot? = nil,
        requestID: AiChatRequestID? = nil,
        runID: AiChatRunID? = nil,
    )
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
    case attachmentDrop([AiChatAttachmentDropProvider])
    case attachmentDropSelection([URL])
    case removeAddedAttachment(AiChatAttachmentID)
    case folderStructureModeChanged(AiChatFolderContextTarget, AiChatFolderStructureMode)
    case openSettingsTapped
    case errorRecoveryTapped
    case rebindContextTapped
    case startNewChatFromRebindTapped
    case submitTapped
    case regenerateTapped
    case requestContextResolved(UUID, AiChatResolvedRequestContext)
    case cancelTapped
    case resetTapped
    case cancelRequestLifecycle(AiChatSessionID)
    case cancelInFlightWork
    case teardownRequested
    case restoreOutcome(
        requestedSessionID: AiChatSessionID,
        AiChatSessionRestoreResult,
        restoreFailure: AiChatSessionRestoreFailure?,
    )
    case executionEvent(AiChatEvent)
    case persistenceFailed(AiChatRequestLock, AiChatExecutionFailure)
    case persistenceRecoverySucceeded(AiChatRequestLock)
    case persistenceRecoveryRetryFailed(AiChatRequestLock, AiChatExecutionFailure)
    case transcriptScrollOffsetsLoaded([AiChatSessionID: CGFloat])
    case transcriptScrollOffsetChanged(AiChatSessionID, CGFloat)

    @CasePathable
    public enum Delegate: CasePathable, Equatable, Sendable {
        case openAISettings
        case requestAttachmentPicker
        case clearCurrentContextSelection
    }
}

public extension AiChatAction {
    static func newChatTapped(seed: AiChatNewChatSelectionSeed?) -> Self {
        seed.map(newChatTappedWithSeed) ?? .newChatTapped
    }

    static func prepareUnpersistedNewChat(seed: AiChatNewChatSelectionSeed?) -> Self {
        seed.map(prepareUnpersistedNewChatWithSeed) ?? .prepareUnpersistedNewChat
    }

    static func prepareUnpersistedNewChatWithContext(
        _ snapshot: AiChatCurrentContextSnapshot,
        seed: AiChatNewChatSelectionSeed?,
    ) -> Self {
        guard let seed else { return .prepareUnpersistedNewChatWithContext(snapshot) }
        return .prepareTransientNewChatWithContext(snapshot, seed)
    }
}

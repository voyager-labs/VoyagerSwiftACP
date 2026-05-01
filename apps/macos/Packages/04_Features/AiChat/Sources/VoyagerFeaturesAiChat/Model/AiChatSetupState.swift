import VoyagerEntitiesAi

public struct AiChatSetupState: Equatable, Sendable {
    public var restoreSessionID: AiChatSessionID?
    public var sessionID: AiChatSessionID?
    public var sessionStatus: AiChatSessionStatus
    public var currentContext: AiChatCurrentContextSnapshot
    public var transcriptHistory: [AiChatMessage]
    public var draftText: String
    public var catalogRows: [AiModelCatalogRow]
    public var selectedModelHandle: AiModelHandle?
    public var lockedModelHandle: AiModelHandle?
    public var lastExecutionFailure: AiChatExecutionFailure?

    public init(
        restoreSessionID: AiChatSessionID? = nil,
        sessionID: AiChatSessionID? = nil,
        sessionStatus: AiChatSessionStatus = .idle,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        transcriptHistory: [AiChatMessage] = [],
        draftText: String = "",
        catalogRows: [AiModelCatalogRow] = [],
        selectedModelHandle: AiModelHandle? = nil,
        lockedModelHandle: AiModelHandle? = nil,
        lastExecutionFailure: AiChatExecutionFailure? = nil
    ) {
        self.restoreSessionID = restoreSessionID
        self.sessionID = sessionID
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.transcriptHistory = transcriptHistory
        self.draftText = draftText
        self.catalogRows = catalogRows
        self.selectedModelHandle = selectedModelHandle
        self.lockedModelHandle = lockedModelHandle
        self.lastExecutionFailure = lastExecutionFailure
    }
}

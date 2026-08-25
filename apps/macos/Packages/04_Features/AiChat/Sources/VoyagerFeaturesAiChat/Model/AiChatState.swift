import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public struct AiModelListFailure: Equatable, Sendable {
    public var message: String
    public var reason: AiModelListFailureReason

    public init(message: String, reason: AiModelListFailureReason = .generic) {
        self.message = message
        self.reason = reason
    }
}

public enum AiModelListFailureReason: Equatable, Sendable {
    case generic
    case unsupportedProvider
}

public enum AiChatProviderConnectionSnapshot: Equatable, Sendable {
    case unknown
    case known([AiProvider])
}

public enum AiChatModelListState: Equatable, Sendable {
    case idle
    case loading
    case loaded([AiProviderModel])
    case empty
    case failed(AiModelListFailure)
}

public enum AiChatMode: Equatable, Sendable {
    case sessions
    case chat
}

struct AiChatTranscriptHistoryMutationTracker: Equatable {
    var value: UInt64 = 0

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

struct AiChatStreamingAssistantDraftMutationTracker: Equatable {
    var value: UInt64 = 0

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

struct AiChatNewChatPreparationMutationTracker: Equatable {
    var value: UInt64 = 0

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

struct AiChatInspectorReopenMutationBaseline: Equatable {
    struct PendingPersistence: Equatable {
        let sessionID: AiChatSessionID
        let revision: UInt64
    }

    var sessionID: AiChatSessionID?
    var revision: UInt64 = 0
    var pendingPersistence: [AiChatRequestID: PendingPersistence] = [:]

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

public enum AiChatSessionRowMergeResult: Equatable, Sendable {
    case rejected
    case unchanged
    case merged

    public var acceptsRow: Bool {
        self != .rejected
    }

    public var permitsSnapshotPayload: Bool {
        self == .merged
    }
}

public struct AiChatSessionListState: Equatable, Sendable {
    public var allRows: [AiChatSessionSummary]
    public var rows: [AiChatSessionSummary]
    public var query: String
    public var isLoading: Bool
    public var hasLoadedRows: Bool
    public var errorMessage: String?
    public var selectedSessionID: AiChatSessionID?
    public var unreadCompletedSessionIDs: Set<AiChatSessionID>
    public var deletedSessionIDs: Set<AiChatSessionID>
    public var renamingSessionID: AiChatSessionID?
    public var renameDraftText: String

    public init(
        allRows: [AiChatSessionSummary] = [],
        rows: [AiChatSessionSummary]? = nil,
        query: String = "",
        isLoading: Bool = false,
        hasLoadedRows: Bool = false,
        errorMessage: String? = nil,
        selectedSessionID: AiChatSessionID? = nil,
        unreadCompletedSessionIDs: Set<AiChatSessionID> = [],
        deletedSessionIDs: Set<AiChatSessionID> = [],
        renamingSessionID: AiChatSessionID? = nil,
        renameDraftText: String = "",
    ) {
        self.allRows = allRows
        self.query = query
        self.isLoading = isLoading
        self.hasLoadedRows = hasLoadedRows
        self.errorMessage = errorMessage
        self.selectedSessionID = selectedSessionID
        self.unreadCompletedSessionIDs = unreadCompletedSessionIDs
        self.deletedSessionIDs = deletedSessionIDs
        self.renamingSessionID = renamingSessionID
        self.renameDraftText = renameDraftText
        self.rows = rows ?? Self.filteredRows(from: allRows, query: query)
    }

    public mutating func setLoadedRows(_ rows: [AiChatSessionSummary]) {
        hasLoadedRows = true
        let visibleRows = rows.filter { !deletedSessionIDs.contains($0.sessionID) }
        allRows = visibleRows
        self.rows = Self.filteredRows(from: visibleRows, query: query)
    }

    public mutating func updateQuery(_ query: String) {
        self.query = query
        rows = Self.filteredRows(from: allRows, query: query)
    }

    public mutating func removeRow(sessionID: AiChatSessionID) {
        deletedSessionIDs.insert(sessionID)
        allRows.removeAll { $0.sessionID == sessionID }
        rows = Self.filteredRows(from: allRows, query: query)
        unreadCompletedSessionIDs.remove(sessionID)
        if selectedSessionID == sessionID {
            selectedSessionID = nil
        }
        if renamingSessionID == sessionID {
            renamingSessionID = nil
            renameDraftText = ""
        }
    }

    public mutating func replaceRow(_ row: AiChatSessionSummary) {
        guard !deletedSessionIDs.contains(row.sessionID) else { return }
        if let index = allRows.firstIndex(where: { $0.sessionID == row.sessionID }) {
            allRows[index] = row
        } else {
            allRows.append(row)
        }
        allRows.sort { lhs, rhs in
            if lhs.updatedAtMs == rhs.updatedAtMs {
                return lhs.sessionID.rawValue.uuidString < rhs.sessionID.rawValue.uuidString
            }
            return lhs.updatedAtMs > rhs.updatedAtMs
        }
        rows = Self.filteredRows(from: allRows, query: query)
    }

    @discardableResult
    public mutating func replaceRowIfNewer(_ row: AiChatSessionSummary) -> AiChatSessionRowMergeResult {
        guard !deletedSessionIDs.contains(row.sessionID) else { return .rejected }
        if let currentRow = allRows.first(where: { $0.sessionID == row.sessionID }) {
            guard !currentRow.isNewer(than: row) else { return .rejected }
            if row == currentRow {
                replaceRow(row)
                return .unchanged
            }
            guard row.isNewer(than: currentRow) else { return .rejected }
        }
        replaceRow(row)
        return .merged
    }

    public mutating func beginRenaming(sessionID: AiChatSessionID) {
        renamingSessionID = sessionID
        renameDraftText = allRows.first(where: { $0.sessionID == sessionID })?.title ?? ""
    }

    public mutating func cancelRenaming() {
        renamingSessionID = nil
        renameDraftText = ""
    }

    static func filteredRows(from rows: [AiChatSessionSummary], query: String) -> [AiChatSessionSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return rows }
        let normalizedQuery = trimmedQuery.localizedLowercase
        return rows.filter { row in
            [row.title, row.preview, row.contextTitle, row.searchText]
                .compactMap { $0?.localizedLowercase }
                .contains { $0.contains(normalizedQuery) }
        }
    }
}

public enum AiChatCurrentContextFolderStructureSource: String, Codable, Equatable, Hashable, Sendable {
    case reference
    case item
    case itemReference
    case attachment
}

public struct AiChatCurrentContextFolderStructureKey: Codable, Equatable, Hashable, Sendable {
    public let source: AiChatCurrentContextFolderStructureSource
    public let canonicalPath: String

    public init(source: AiChatCurrentContextFolderStructureSource, canonicalPath: String) {
        self.source = source
        self.canonicalPath = canonicalPath
    }
}

public typealias AiChatCurrentContextFolderStructureModes = [
    AiChatCurrentContextFolderStructureKey: AiChatFolderStructureMode
]

@ObservableState
public struct AiChatState: Equatable, Sendable {
    var cancellationOwnerID = UUID()
    var newChatPreparationMutationTracker = AiChatNewChatPreparationMutationTracker()
    var transcriptHistoryMutationTracker = AiChatTranscriptHistoryMutationTracker()
    var streamingAssistantDraftMutationTracker = AiChatStreamingAssistantDraftMutationTracker()
    var inspectorReopenMutationBaseline = AiChatInspectorReopenMutationBaseline()
    public var restoreSessionID: AiChatSessionID?
    public var deferredChatSessionRestoreID: AiChatSessionID?
    public var restoreOutcome: AiChatSessionRestoreResult?
    public var restoreFailure: AiChatSessionRestoreFailure?
    public var mode: AiChatMode
    public var sessionList: AiChatSessionListState
    public var sessionID: AiChatSessionID?
    public var preparedTransientSessionID: AiChatSessionID?
    public var emptyDraftSessionID: AiChatSessionID?
    public var pendingEmptyDraftDeletionSessionIDs: Set<AiChatSessionID>
    public var currentSessionCustomTitle: String?
    public var sessionStatus: AiChatSessionStatus
    public var currentContext: AiChatCurrentContextSnapshot
    public var currentContextFolderStructureModes: AiChatCurrentContextFolderStructureModes
    public var addedAttachments: [AiChatAttachmentDraft]
    public var transcriptHistory: [AiChatMessage] {
        didSet {
            transcriptHistoryMutationTracker.value &+= 1
        }
    }

    public var draftText: String
    public var streamingAssistantDraft: String? {
        didSet {
            streamingAssistantDraftMutationTracker.value &+= 1
        }
    }

    public var transcriptSearch: AiChatTranscriptSearchState
    public var transcriptAutoScrollVersion: Int
    public var catalogRows: [AiModelCatalogRow]
    public var modelListState: AiChatModelListState
    public var selectedModelHandle: AiModelHandle?
    public var selectedThinking: AiThinkingSelection?
    public var unavailableSelectedModelHandle: AiModelHandle?
    public var lockedModelHandle: AiModelHandle?
    public var lastExecutionFailure: AiChatExecutionFailure?
    public var lastRequestContext: AiChatLockedRequestContextSnapshot?
    public var lastRequestContextModelHandle: AiModelHandle?
    public var pendingRequestStart: AiChatPendingRequestStart?
    public var backgroundPendingRequestStarts: [UUID: AiChatPendingRequestStart]
    public var executionPhase: AiChatExecutionPhase
    public var backgroundExecutionPhases: [AiChatRequestID: AiChatExecutionPhase]
    public var productMetricOperations: [AiChatRequestID: AiChatProductMetricOperation]
    public var modelListRequestID: UUID?
    public var modelListProvider: AiProvider?
    public var modelListProviderOrder: [AiProvider]
    public var modelListPendingProviders: Set<AiProvider>
    public var modelListLoadedModelsByProvider: [AiProvider: [AiProviderModel]]
    public var modelListFailedProviders: [AiProvider: AiModelListFailure]
    public var providerConnectionSnapshot: AiChatProviderConnectionSnapshot
    public var availableModelsByProvider: [AiProvider: [AiProviderModel]]
    public var transcriptScrollOffsets: [AiChatSessionID: CGFloat]

    mutating func resetTranscriptSearchIfSessionChanges(to nextSessionID: AiChatSessionID?) {
        guard sessionID != nextSessionID else { return }
        transcriptSearch.reset()
    }

    /// 기존 session runtime을 보존한 채 Chat 표시 의미 상태만 준비한다.
    @discardableResult
    public mutating func prepareChatPresentation(for sessionID: AiChatSessionID) -> Bool {
        guard self.sessionID == sessionID else { return false }

        deferredChatSessionRestoreID = nil
        sessionList.cancelRenaming()
        sessionList.errorMessage = nil
        if let restoreSessionID, restoreSessionID != sessionID {
            self.restoreSessionID = nil
            settleCancelledSessionRestoreIfNeeded()
            if sessionList.selectedSessionID == restoreSessionID {
                sessionList.selectedSessionID = nil
            }
        }
        restoreOutcome = nil
        restoreFailure = nil
        if let promotedExecutionPhase = takePromotedNavigationExecutionPhase(for: sessionID) {
            executionPhase = promotedExecutionPhase
        }
        mode = .chat
        return true
    }

    /// inactive cache에서 활성화 시 복원할 persisted Chat session 의도만 준비한다.
    public mutating func prepareDeferredChatSessionRestore(for sessionID: AiChatSessionID) {
        sessionList.cancelRenaming()
        sessionList.errorMessage = nil
        sessionList.selectedSessionID = sessionID
        deferredChatSessionRestoreID = sessionID
        restoreSessionID = nil
        restoreOutcome = nil
        restoreFailure = nil
        mode = .sessions
    }

    /// 준비된 persisted Chat session 의도를 active restore lifecycle로 승격한다.
    public mutating func beginDeferredChatSessionRestore(for sessionID: AiChatSessionID) -> Bool {
        guard self.sessionID != sessionID,
              restoreSessionID == nil,
              emptyDraftSessionID != sessionID,
              deferredChatSessionRestoreID == sessionID
        else { return false }
        deferredChatSessionRestoreID = nil
        beginSessionRestore(for: sessionID)
        sessionList.selectedSessionID = sessionID
        restoreOutcome = nil
        restoreFailure = nil
        mode = .sessions
        return true
    }

    mutating func takePromotedNavigationExecutionPhase(
        for sessionID: AiChatSessionID,
    ) -> AiChatExecutionPhase? {
        switch executionPhase {
        case let .processing(lock) where lock.context.sessionID == sessionID:
            return .processing(lock)
        case let .completed(lock) where lock.context.sessionID == sessionID:
            return .completed(lock)
        case let .failed(lock, failure) where lock.context.sessionID == sessionID:
            return .failed(lock, failure)
        case let .cancelled(lock) where lock.context.sessionID == sessionID:
            return .cancelled(lock)
        case let .persistenceRecovery(lock, failure) where lock.context.sessionID == sessionID:
            return .persistenceRecovery(lock, failure)
        default:
            break
        }

        guard let match = backgroundExecutionPhases
            .filter({ _, phase in phase.lock?.context.sessionID == sessionID })
            .max(by: { lhs, rhs in
                lhs.value.navigationPromotionPriority < rhs.value.navigationPromotionPriority
            })
        else { return nil }
        backgroundExecutionPhases[match.key] = nil
        return match.value
    }

    /// inactive cache에서 loaded runtime과 History route intent를 분리한다.
    public mutating func prepareInactiveSessionsPresentation(for sessionID: AiChatSessionID) {
        if self.sessionID == sessionID {
            _ = prepareSessionsPresentation(for: sessionID)
        } else {
            prepareDeferredChatSessionRestore(for: sessionID)
        }
    }

    public mutating func prepareSessionsPresentation(for sessionID: AiChatSessionID) -> Bool {
        deferredChatSessionRestoreID = nil
        sessionList.cancelRenaming()
        sessionList.errorMessage = nil
        restoreOutcome = nil
        restoreFailure = nil
        mode = .sessions
        resetTranscriptSearchIfSessionChanges(to: sessionID)
        self.sessionID = sessionID
        sessionList.selectedSessionID = sessionID
        guard let restoreSessionID, restoreSessionID != sessionID else { return false }
        self.restoreSessionID = nil
        settleCancelledSessionRestoreIfNeeded()
        return true
    }

    public init(
        restoreSessionID: AiChatSessionID? = nil,
        deferredChatSessionRestoreID: AiChatSessionID? = nil,
        restoreOutcome: AiChatSessionRestoreResult? = nil,
        restoreFailure: AiChatSessionRestoreFailure? = nil,
        mode: AiChatMode = .sessions,
        sessionList: AiChatSessionListState = .init(),
        sessionID: AiChatSessionID? = nil,
        preparedTransientSessionID: AiChatSessionID? = nil,
        emptyDraftSessionID: AiChatSessionID? = nil,
        pendingEmptyDraftDeletionSessionIDs: Set<AiChatSessionID> = [],
        currentSessionCustomTitle: String? = nil,
        sessionStatus: AiChatSessionStatus = .idle,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        currentContextFolderStructureModes: AiChatCurrentContextFolderStructureModes = [:],
        addedAttachments: [AiChatAttachmentDraft] = [],
        transcriptHistory: [AiChatMessage] = [],
        draftText: String = "",
        streamingAssistantDraft: String? = nil,
        transcriptSearch: AiChatTranscriptSearchState = .init(),
        transcriptAutoScrollVersion: Int = 0,
        catalogRows: [AiModelCatalogRow] = [],
        modelListState: AiChatModelListState? = nil,
        selectedModelHandle: AiModelHandle? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        unavailableSelectedModelHandle: AiModelHandle? = nil,
        lockedModelHandle: AiModelHandle? = nil,
        lastExecutionFailure: AiChatExecutionFailure? = nil,
        lastRequestContext: AiChatLockedRequestContextSnapshot? = nil,
        lastRequestContextModelHandle: AiModelHandle? = nil,
        pendingRequestStart: AiChatPendingRequestStart? = nil,
        backgroundPendingRequestStarts: [UUID: AiChatPendingRequestStart] = [:],
        executionPhase: AiChatExecutionPhase = .idle,
        backgroundExecutionPhases: [AiChatRequestID: AiChatExecutionPhase] = [:],
        productMetricOperations: [AiChatRequestID: AiChatProductMetricOperation] = [:],
        modelListRequestID: UUID? = nil,
        modelListProvider: AiProvider? = nil,
        modelListProviderOrder: [AiProvider] = [],
        modelListPendingProviders: Set<AiProvider> = [],
        modelListLoadedModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        modelListFailedProviders: [AiProvider: AiModelListFailure] = [:],
        providerConnectionSnapshot: AiChatProviderConnectionSnapshot = .unknown,
        availableModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        transcriptScrollOffsets: [AiChatSessionID: CGFloat] = [:],
    ) {
        self.restoreSessionID = restoreSessionID
        self.deferredChatSessionRestoreID = deferredChatSessionRestoreID
        self.restoreOutcome = restoreOutcome
        self.restoreFailure = restoreFailure
        self.mode = mode
        self.sessionList = sessionList
        self.sessionID = sessionID
        self.preparedTransientSessionID = preparedTransientSessionID
        self.emptyDraftSessionID = emptyDraftSessionID
        self.pendingEmptyDraftDeletionSessionIDs = pendingEmptyDraftDeletionSessionIDs
        self.currentSessionCustomTitle = currentSessionCustomTitle
        self.sessionStatus = sessionStatus
        self.currentContext = currentContext
        self.currentContextFolderStructureModes = currentContextFolderStructureModes
        self.addedAttachments = addedAttachments
        self.transcriptHistory = transcriptHistory
        self.draftText = draftText
        self.streamingAssistantDraft = streamingAssistantDraft
        self.transcriptSearch = transcriptSearch
        self.transcriptAutoScrollVersion = transcriptAutoScrollVersion
        let resolvedModelListState = modelListState ?? Self.modelListState(from: catalogRows)
        self.catalogRows = catalogRows.isEmpty ? Self.makeCatalogRows(for: resolvedModelListState) : catalogRows
        self.modelListState = resolvedModelListState
        self.selectedModelHandle = selectedModelHandle
        self.selectedThinking = selectedThinking
        self.unavailableSelectedModelHandle = unavailableSelectedModelHandle
        self.lockedModelHandle = lockedModelHandle
        self.lastExecutionFailure = lastExecutionFailure
        self.lastRequestContext = lastRequestContext
        self.lastRequestContextModelHandle = lastRequestContextModelHandle
        self.pendingRequestStart = pendingRequestStart
        self.backgroundPendingRequestStarts = backgroundPendingRequestStarts
        self.executionPhase = executionPhase
        self.backgroundExecutionPhases = backgroundExecutionPhases
        self.productMetricOperations = productMetricOperations
        self.modelListRequestID = modelListRequestID
        self.modelListProvider = modelListProvider
        self.modelListProviderOrder = modelListProviderOrder
        self.modelListPendingProviders = modelListPendingProviders
        self.modelListLoadedModelsByProvider = modelListLoadedModelsByProvider
        self.modelListFailedProviders = modelListFailedProviders
        self.providerConnectionSnapshot = providerConnectionSnapshot
        self.availableModelsByProvider = availableModelsByProvider
        self.transcriptScrollOffsets = transcriptScrollOffsets
        inspectorReopenMutationBaseline = .init(sessionID: sessionID)
    }

    public var availableModels: [AiProviderModel] {
        displayModelBuilder.availableModels
    }

    public var currentContextSummaryDisplayModel: AiChatContextSummaryDisplayModel {
        displayModelBuilder.currentContextSummaryDisplayModel
    }

    public var connectionState: AiChatConnectionState {
        displayModelBuilder.connectionState
    }

    public var emptyStateDisplayModel: AiChatEmptyStateDisplayModel {
        displayModelBuilder.emptyStateDisplayModel
    }

    public var chatInputDisplayModel: AiChatInputDisplayModel {
        displayModelBuilder.chatInputDisplayModel
    }

    public var skeletonDisplayModel: AiChatSkeletonDisplayModel {
        displayModelBuilder.skeletonDisplayModel
    }

    public var skeletonSurfaceDisplayModel: AiChatSkeletonSurfaceDisplayModel {
        displayModelBuilder.skeletonSurfaceDisplayModel
    }

    public var streamingAssistantDisplayModel: AiChatStreamingAssistantDisplayModel? {
        displayModelBuilder.streamingAssistantDisplayModel
    }

    public var modelCatalogState: AiChatModelCatalogState {
        displayModelBuilder.modelCatalogState
    }

    public var modelSelectorContentState: AiChatModelSelectorContentState {
        displayModelBuilder.modelSelectorContentState
    }

    public var modelSelectorHasPresentableContent: Bool {
        displayModelBuilder.modelSelectorHasPresentableContent
    }

    public var modelSelectorIsDisabled: Bool {
        displayModelBuilder.modelSelectorIsDisabled
    }

    public var selectedModelDisplayModel: AiChatSelectedModelDisplayModel? {
        displayModelBuilder.selectedModelDisplayModel
    }

    public var lockedModelDisplayModel: AiChatLockedModelDisplayModel? {
        displayModelBuilder.lockedModelDisplayModel
    }

    public var isUntouchedPreparedTransientNewChat: Bool {
        guard let sessionID,
              preparedTransientSessionID == sessionID,
              mode == .chat,
              sessionStatus == .idle,
              restoreSessionID == nil,
              restoreOutcome == nil,
              restoreFailure == nil,
              transcriptHistory.isEmpty,
              draftText.isEmpty,
              streamingAssistantDraft == nil,
              addedAttachments.isEmpty,
              lastRequestContext == nil,
              executionPhase == .idle,
              pendingRequestStart?.sessionID != sessionID,
              !backgroundPendingRequestStarts.values.contains(where: { $0.sessionID == sessionID }),
              !backgroundExecutionPhases.values.contains(where: { phase in
                  phase.isProcessing && phase.lock?.context.sessionID == sessionID
              })
        else { return false }
        return true
    }

    mutating func invalidatePreparedTransientSession(for sessionID: AiChatSessionID? = nil) {
        guard sessionID == nil || preparedTransientSessionID == sessionID else { return }
        preparedTransientSessionID = nil
    }

    mutating func markPreparedTransientSessionAsTouched() {
        invalidatePreparedTransientSession()
    }

    public var hiddenEmptyDraftSessionIDs: Set<AiChatSessionID> {
        var hiddenSessionIDs = pendingEmptyDraftDeletionSessionIDs
        if let emptyDraftSessionID,
           sessionID == emptyDraftSessionID,
           sessionStatus == .idle,
           transcriptHistory.isEmpty,
           streamingAssistantDraft == nil,
           lastRequestContext == nil,
           !executionPhase.isProcessing
        {
            hiddenSessionIDs.insert(emptyDraftSessionID)
        }
        return hiddenSessionIDs
    }

    public var canSubmit: Bool {
        displayModelBuilder.canSubmit
    }

    public var canRegenerate: Bool {
        displayModelBuilder.canRegenerate
    }

    public var requestStatusText: String? {
        displayModelBuilder.requestStatusText
    }

    public var sessionStatusText: String? {
        displayModelBuilder.sessionStatusText
    }

    public var cancelAffordance: AiChatCancelAffordance? {
        displayModelBuilder.cancelAffordance
    }
}

public extension AiChatState {
    mutating func beginSessionRestore(for sessionID: AiChatSessionID) {
        restoreSessionID = sessionID
        sessionStatus = .restoring
    }

    mutating func settleCancelledSessionRestoreIfNeeded() {
        guard sessionStatus == .restoring else { return }
        sessionStatus = sessionID == nil || emptyDraftSessionID == sessionID ? .idle : .active
    }

    /// 동일 session에서 마지막 persisted 기준 이후 사용자 또는 navigation 변경이 발생했는지 반환한다.
    func hasInspectorReopenUserMutation(for sessionID: AiChatSessionID) -> Bool {
        self.sessionID == sessionID
            && inspectorReopenMutationBaseline.sessionID == sessionID
            && newChatPreparationMutationTracker.value != inspectorReopenMutationBaseline.revision
    }

    var newChatPreparationProvenance: AiChatNewChatPreparationProvenance {
        AiChatNewChatPreparationProvenance(
            ownerID: cancellationOwnerID,
            mutationRevision: newChatPreparationMutationTracker.value,
            restoreSessionID: restoreSessionID,
            deferredChatSessionRestoreID: deferredChatSessionRestoreID,
            restoreOutcome: restoreOutcome,
            restoreFailure: restoreFailure,
            mode: mode,
            selectedHistorySessionID: sessionList.selectedSessionID,
            sessionID: sessionID,
            preparedTransientSessionID: preparedTransientSessionID,
            emptyDraftSessionID: emptyDraftSessionID,
            currentSessionCustomTitle: currentSessionCustomTitle,
            sessionStatus: sessionStatus,
            currentContext: currentContext,
            currentContextFolderStructureModes: currentContextFolderStructureModes,
            addedAttachments: addedAttachments,
            transcriptHistory: transcriptHistory,
            draftText: draftText,
            streamingAssistantDraft: streamingAssistantDraft,
            selectedModelHandle: selectedModelHandle,
            selectedThinking: selectedThinking,
            unavailableSelectedModelHandle: unavailableSelectedModelHandle,
            pendingRequestStart: pendingRequestStart,
            executionPhase: executionPhase,
        )
    }

    func matchesInspectorLiveRuntimeReopenProvenance(
        _ provenance: AiChatNewChatPreparationProvenance,
    ) -> Bool {
        let current = newChatPreparationProvenance
        return current.ownerID == provenance.ownerID
            && current.mutationRevision == provenance.mutationRevision
            && current.restoreSessionID == provenance.restoreSessionID
            && current.deferredChatSessionRestoreID == provenance.deferredChatSessionRestoreID
            && current.mode == provenance.mode
            && current.selectedHistorySessionID == provenance.selectedHistorySessionID
            && current.sessionID == provenance.sessionID
            && current.preparedTransientSessionID == provenance.preparedTransientSessionID
            && current.emptyDraftSessionID == provenance.emptyDraftSessionID
            && current.sessionStatus == provenance.sessionStatus
    }

    func matchesInspectorNewChatPreparationProvenance(
        _ provenance: AiChatNewChatPreparationProvenance,
    ) -> Bool {
        let current = newChatPreparationProvenance
        return current.ownerID == provenance.ownerID
            && current.mutationRevision == provenance.mutationRevision
            && current.restoreSessionID == provenance.restoreSessionID
            && current.deferredChatSessionRestoreID == provenance.deferredChatSessionRestoreID
            && current.restoreOutcome == provenance.restoreOutcome
            && current.restoreFailure == provenance.restoreFailure
            && current.mode == provenance.mode
            && current.selectedHistorySessionID == provenance.selectedHistorySessionID
            && current.sessionID == provenance.sessionID
            && current.preparedTransientSessionID == provenance.preparedTransientSessionID
            && current.emptyDraftSessionID == provenance.emptyDraftSessionID
            && current.currentSessionCustomTitle == provenance.currentSessionCustomTitle
            && current.sessionStatus == provenance.sessionStatus
            && current.currentContext == provenance.currentContext
            && current.currentContextFolderStructureModes == provenance.currentContextFolderStructureModes
            && current.addedAttachments == provenance.addedAttachments
            && current.transcriptHistory == provenance.transcriptHistory
            && current.draftText == provenance.draftText
            && current.streamingAssistantDraft == provenance.streamingAssistantDraft
            && current.pendingRequestStart == provenance.pendingRequestStart
            && current.executionPhase == provenance.executionPhase
    }
}

extension AiChatState {
    mutating func resetInspectorReopenMutationBaseline(for sessionID: AiChatSessionID) {
        inspectorReopenMutationBaseline.sessionID = sessionID
        inspectorReopenMutationBaseline.revision = newChatPreparationMutationTracker.value
    }

    mutating func prepareInspectorReopenPersistenceBaseline(
        requestID: AiChatRequestID,
        sessionID: AiChatSessionID,
    ) {
        inspectorReopenMutationBaseline.pendingPersistence[requestID] = .init(
            sessionID: sessionID,
            revision: newChatPreparationMutationTracker.value,
        )
    }

    mutating func completeInspectorReopenPersistenceBaseline(requestID: AiChatRequestID) -> Bool {
        guard let pending = inspectorReopenMutationBaseline.pendingPersistence.removeValue(forKey: requestID),
              sessionID == pending.sessionID
        else { return false }
        let hasNewerMutation = newChatPreparationMutationTracker.value != pending.revision
        inspectorReopenMutationBaseline.sessionID = pending.sessionID
        inspectorReopenMutationBaseline.revision = pending.revision
        return hasNewerMutation
    }
}

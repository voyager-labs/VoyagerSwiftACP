import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

public struct FilterSnapshot: Equatable {
    let scopeSelection: ComposerScopeSelection
    public let conditionEditors: IdentifiedArrayOf<ConditionEditorState>
    let includeSubfolders: Bool
    let includeDirectories: Bool

    init(
        scopeSelection: ComposerScopeSelection,
        conditionEditors: IdentifiedArrayOf<ConditionEditorState>,
        includeSubfolders: Bool,
        includeDirectories: Bool,
    ) {
        self.scopeSelection = scopeSelection
        self.conditionEditors = conditionEditors
        self.includeSubfolders = includeSubfolders
        self.includeDirectories = includeDirectories
    }

    init(
        scopes: [String],
        conditionEditors: IdentifiedArrayOf<ConditionEditorState>,
        includeSubfolders: Bool = true,
        includeDirectories: Bool = false,
    ) {
        self.init(
            scopeSelection: ComposerScopeSelection.fromLegacyScopes(scopes),
            conditionEditors: conditionEditors,
            includeSubfolders: includeSubfolders,
            includeDirectories: includeDirectories,
        )
    }
}

public struct ConditionDisplayState: Equatable {
    public var values: [String]
    public var unitValueState: UnitValueState?

    public init(values: [String], unitValueState: UnitValueState?) {
        self.values = values
        self.unitValueState = unitValueState
    }
}

struct ComposerQueryRecoveryContext: Equatable {
    enum Stage: Equatable {
        case search(UUID)
        case filters(UUID)
    }

    let rawText: String
    let capturedInputRevision: UInt64
    var stage: Stage
}

@ObservableState
public struct ComposerState: Equatable {
    public var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    public var valuePicker: ValuePickerFeature.State = .init()

    public var scopeEditor: ComposerScopeEditorState = .init()
    var lastScopeChangeFeedback: ComposerScopeChangeFeedback?

    public var isPresented: Bool = false
    public var collectionContext: CollectionContext?
    public var openedCollectionURL: URL?
    public var openedCollectionCompatibility: CollectionFileCompatibilityMetadata?
    public var isCollectionMode: Bool = false
    public var pendingSearchQuery: String?
    public var includeDirectories: Bool = false
    public var cancellationOwnerID: UUID?

    public var text: String = ""
    var inputRevision: UInt64 = 0
    var queryRecoveryContext: ComposerQueryRecoveryContext?
    public var scopes: [String] {
        get { scopeEditor.selection.legacyScopePaths }
        set { scopeEditor.selection = ComposerScopeSelection.fromLegacyScopes(newValue) }
    }

    public var conditionEditors: IdentifiedArrayOf<ConditionEditorState> = []
    public var conditions: [Condition] {
        conditionEditors.map(\.condition)
    }

    public var conditionDisplayByKey: [String: ConditionDisplayState] {
        Dictionary(uniqueKeysWithValues: conditionEditors.compactMap { editor in
            editor.displayState.map { (editor.condition.property.key, $0) }
        })
    }

    public var operatorOptionsByKey: [String: [String]] {
        Dictionary(uniqueKeysWithValues: conditionEditors.map {
            ($0.condition.property.key, $0.condition.property.operatorOptions.map(\.code))
        })
    }

    public var focusRequestID: Int = 0

    public var history: [FilterSnapshot] = []
    public var redoHistory: [FilterSnapshot] = []

    public var isLoadingSearch: Bool = false
    public var isLoadingFilters: Bool = false
    public var isFilteringInFlight: Bool = false
    public var queryRenderPhase: ComposerQueryRenderPhase = .idle
    public var transientFeedback: ComposerTransientFeedback?
    public var submittedSearchFilters: VoyagerShared.SearchFiltersPayload?
    public var activeSearchRequestID: UUID?
    public var activeFiltersRequestID: UUID?
    public var lastAcceptedSearchRequestID: UUID?
    public var lastAcceptedFiltersRequestID: UUID?
    public var lastFailedFiltersRequestID: UUID?

    public var lastSearchResponse: VoyagerShared.SearchResponsePayload?
    public var lastFiltersResponse: VoyagerShared.SearchResponsePayload?
    public var searchStartedAt: Date?
    public var filtersStartedAt: Date?
    var activeFiltersMetricSource: String?
    public var hasSubmittedInSession: Bool = false

    public init() {}

    mutating func setTextFromUserIntent(_ text: String) {
        inputRevision &+= 1
        self.text = text
    }

    mutating func replaceTextAndDiscardQueryRecovery(_ text: String) {
        inputRevision &+= 1
        queryRecoveryContext = nil
        self.text = text
    }

    mutating func clearTextForSubmit() {
        text = ""
    }

    mutating func captureQueryRecovery(rawText: String, requestID: UUID) {
        queryRecoveryContext = ComposerQueryRecoveryContext(
            rawText: rawText,
            capturedInputRevision: inputRevision,
            stage: .search(requestID),
        )
    }

    func queryRecoveryRawText(for stage: ComposerQueryRecoveryContext.Stage) -> String? {
        guard let queryRecoveryContext,
              queryRecoveryContext.stage == stage
        else {
            return nil
        }
        return queryRecoveryContext.rawText
    }

    mutating func retargetQueryRecovery(from searchRequestID: UUID, to filtersRequestID: UUID) {
        guard queryRecoveryContext?.stage == .search(searchRequestID) else { return }
        queryRecoveryContext?.stage = .filters(filtersRequestID)
    }

    mutating func restoreQueryRecoveryIfEligible(for stage: ComposerQueryRecoveryContext.Stage) {
        defer { queryRecoveryContext = nil }
        guard let context = queryRecoveryContext,
              context.stage == stage,
              context.capturedInputRevision == inputRevision
        else {
            return
        }
        text = context.rawText
    }

    mutating func discardQueryRecovery() {
        queryRecoveryContext = nil
    }

    public var canUndo: Bool {
        !history.isEmpty
    }

    public var canRedo: Bool {
        !redoHistory.isEmpty
    }

    public func collectionContext(query: String) -> CollectionContext {
        CollectionContext(
            query: query,
            scopes: scopeEditor.selection.legacyScopePaths,
            excludedScopes: scopeEditor.selection.exceptions.map(\.path),
            includeSubfolders: scopeEditor.effectiveIncludeSubfolders,
            includeDirectories: includeDirectories,
            conditions: conditions,
        )
    }

    public mutating func commitCurrentScopeDraft() {
        scopeEditor.committedSelection = scopeEditor.selection
        scopeEditor.committedIncludeSubfolders = scopeEditor.includeSubfolders
    }

    public var isSemanticallyRootOnly: Bool {
        scopeEditor.selection.isRootOnly
    }

    var scopeSummary: ComposerScopeSummary {
        scopeEditor.summary
    }

    public var shouldAutoApplyScopeChange: Bool {
        hasCommittedQuerySearch
            || hasCommittedScopeSearch
            || conditions.contains(where: \.isExecutionReady)
    }

    public var hasCommittedQuerySearch: Bool {
        let trimmedCollectionQuery = collectionContext?.query.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedPendingQuery = pendingSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmedCollectionQuery.isEmpty || !trimmedPendingQuery.isEmpty
    }

    public var hasCommittedScopeSearch: Bool {
        if let collectionContext, !collectionContext.scopes.isEmpty {
            return true
        }
        if let submittedSearchFilters, !submittedSearchFilters.scopes.isEmpty {
            return true
        }
        if let scopes = lastFiltersResponse?.appliedFilters?.scopes, !scopes.isEmpty {
            return true
        }
        if let scopes = lastSearchResponse?.appliedFilters?.scopes, !scopes.isEmpty {
            return true
        }
        return false
    }

    public var lastAppliedIncludeSubfolders: Bool? {
        if let value = collectionContext?.includeSubfolders {
            return value
        }
        if let value = lastFiltersResponse?.appliedFilters?.includeSubfolders {
            return value
        }
        if let value = lastSearchResponse?.appliedFilters?.includeSubfolders {
            return value
        }
        return submittedSearchFilters?.includeSubfolders
    }

    public var isCollectionSearching: Bool {
        let isSearching = isLoadingSearch
            || isLoadingFilters
            || queryRenderPhase == .chipsAppliedPendingList
        let hasContext = isCollectionMode
            || pendingSearchQuery != nil
            || !scopeEditor.selection.legacyScopePaths.isEmpty
            || !conditions.isEmpty
        return isSearching && hasContext
    }

    mutating func pushHistory() {
        history.append(
            FilterSnapshot(
                scopeSelection: scopeEditor.selection,
                conditionEditors: conditionEditors,
                includeSubfolders: scopeEditor.includeSubfolders,
                includeDirectories: includeDirectories,
            ),
        )
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        redoHistory.removeAll()
    }

    public mutating func clearHistory() {
        history.removeAll()
        redoHistory.removeAll()
    }

    public mutating func beginScopeEditing(path: String?) {
        scopeEditor.editingPath = path
        scopeEditor.entryMode = path == nil ? .add : .edit
        scopeEditor.isPresented = true
    }

    mutating func resetScopeEditorInteractionState(clearQuery: Bool) {
        scopeEditor.editingPath = nil
        scopeEditor.entryMode = .add
        scopeEditor.treeNeighborhoodSeedItems = []
        if clearQuery {
            scopeEditor.queryText = ""
        }
    }

    public mutating func applyCollectionDraftRestorePayload(
        _ payload: CollectionDraftRestorePayload,
        uuid: () -> UUID = UUID.init,
    ) {
        let trimmedQuery = payload.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        let restoredText = payload.openedURL == nil ? payload.context.query : ""
        replaceTextAndDiscardQueryRecovery(restoredText)
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.context.scopes,
            exceptions: payload.context.excludedScopes,
            includeSubfolders: payload.context.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.context.includeSubfolders
        includeDirectories = payload.context.includeDirectories
        replaceConditions(payload.context.conditions, uuid: uuid)
        propertyPicker = ConditionPropertyPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    public mutating func applyCollectionNavigationComposerPayload(
        _ payload: CollectionNavigationStatePayload,
        uuid: () -> UUID = UUID.init,
    ) {
        let trimmedQuery = payload.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        replaceTextAndDiscardQueryRecovery(payload.composerText)
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.scopes,
            exceptions: payload.excludedScopes,
            includeSubfolders: payload.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.includeSubfolders
        includeDirectories = payload.includeDirectories
        replaceConditions(payload.conditions, uuid: uuid)
        propertyPicker = ConditionPropertyPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    public mutating func applyCollectionOpenRestorationComposerPayload(
        _ payload: CollectionOpenRestorationPayload,
        registryClient: RegistryClient,
        uuid: () -> UUID = UUID.init,
    ) {
        collectionContext = payload.context
        openedCollectionURL = payload.navigation.flatMap { navigation in
            if case let .file(url, _) = navigation.kind { return url }
            return nil
        }
        openedCollectionCompatibility = payload.compatibility
        isCollectionMode = true
        pendingSearchQuery = payload.context.query.isEmpty ? nil : payload.context.query
        replaceTextAndDiscardQueryRecovery(payload.context.query)
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.context.scopes,
            exceptions: payload.context.excludedScopes,
            includeSubfolders: payload.context.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.context.includeSubfolders
        scopeEditor.committedSelection = selection
        scopeEditor.committedIncludeSubfolders = payload.context.includeSubfolders
        scopeEditor.isPresented = false
        resetScopeEditorInteractionState(clearQuery: true)
        scopeEditor.listState = .defaultCandidates
        scopeEditor.candidateItems = []
        includeDirectories = payload.context.includeDirectories
        replaceConditions(payload.context.conditions, uuid: uuid)
        propertyPicker = ConditionPropertyPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
        resetCollectionOpenLifecycleState()
        let filters = buildFilters(from: self)
        applyAppliedFilters(
            .init(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            state: &self,
            registryClient: registryClient,
            uuid: uuid,
        )
        lastFiltersResponse = nil
        lastSearchResponse = nil
    }

    private mutating func resetCollectionOpenLifecycleState() {
        lastScopeChangeFeedback = nil
        isLoadingSearch = false
        isLoadingFilters = false
        isFilteringInFlight = false
        queryRenderPhase = .idle
        transientFeedback = nil
        submittedSearchFilters = nil
        activeSearchRequestID = nil
        activeFiltersRequestID = nil
        lastAcceptedSearchRequestID = nil
        lastAcceptedFiltersRequestID = nil
        lastFailedFiltersRequestID = nil
        searchStartedAt = nil
        filtersStartedAt = nil
        activeFiltersMetricSource = nil
        hasSubmittedInSession = false
    }

    mutating func replaceConditions(_ conditions: [Condition], uuid: () -> UUID) {
        conditionEditors = IdentifiedArray(uniqueElements: conditions.map { condition in
            .init(
                id: uuid(),
                condition: condition,
            )
        })
    }

    public mutating func applyHydratedCollectionOpenComposerPayload(
        _ payload: CollectionHydratedOpenPayload,
        isNavigationQueryEmpty: Bool,
    ) {
        lastFiltersResponse = payload.lastFiltersResponse
        lastSearchResponse = payload
            .lastSearchResponse ?? (isNavigationQueryEmpty ? nil : payload.lastFiltersResponse)
    }
}

extension ComposerState {
    var hasMatchingScopeChangeFeedback: Bool {
        guard let lastScopeChangeFeedback else { return false }
        return lastScopeChangeFeedback.matchesCurrentScope(
            selection: scopeEditor.selection,
            includeSubfolders: scopeEditor.includeSubfolders,
        )
    }

    mutating func markScopeChangeFeedbackPending(_ pendingResultRequest: ScopeFeedbackPendingRequest) {
        guard let feedback = lastScopeChangeFeedback,
              history.count == feedback.historyDepthAfterCommit,
              feedback.matchesCurrentScope(
                  selection: scopeEditor.selection,
                  includeSubfolders: scopeEditor.includeSubfolders,
              )
        else {
            return
        }
        lastScopeChangeFeedback = feedback.updating(
            pendingResultRequest: pendingResultRequest,
            phase: .delayed,
        )
    }

    mutating func retargetScopeChangeFeedbackPending(
        from expectedPendingResultRequest: ScopeFeedbackPendingRequest,
        to pendingResultRequest: ScopeFeedbackPendingRequest,
    ) {
        guard let feedback = lastScopeChangeFeedback,
              feedback.pendingResultRequest == expectedPendingResultRequest
        else {
            return
        }
        lastScopeChangeFeedback = feedback.updating(
            pendingResultRequest: pendingResultRequest,
            phase: .delayed,
        )
    }

    mutating func resolveScopeChangeFeedback(
        _ pendingResultRequest: ScopeFeedbackPendingRequest,
        phase: ComposerScopeChangeFeedbackPhase,
    ) {
        guard let feedback = lastScopeChangeFeedback,
              feedback.pendingResultRequest == pendingResultRequest
        else {
            return
        }
        lastScopeChangeFeedback = ComposerScopeChangeFeedback(
            id: feedback.id,
            beforeScope: feedback.beforeScope,
            afterScope: feedback.afterScope,
            origin: feedback.origin,
            phase: phase,
            pendingResultRequest: nil,
            historyDepthAfterCommit: feedback.historyDepthAfterCommit,
            redoDepthAfterCommit: feedback.redoDepthAfterCommit,
        )
    }
}

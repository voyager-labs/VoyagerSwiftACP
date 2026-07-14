import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

public struct FilterSnapshot: Equatable {
    let scopeSelection: ComposerScopeSelection
    public let conditions: [Condition]
    public let conditionDisplayByKey: [String: ConditionDisplayState]
    let includeSubfolders: Bool
    let includeDirectories: Bool

    init(
        scopeSelection: ComposerScopeSelection,
        conditions: [Condition],
        conditionDisplayByKey: [String: ConditionDisplayState],
        includeSubfolders: Bool,
        includeDirectories: Bool,
    ) {
        self.scopeSelection = scopeSelection
        self.conditions = conditions
        self.conditionDisplayByKey = conditionDisplayByKey
        self.includeSubfolders = includeSubfolders
        self.includeDirectories = includeDirectories
    }

    init(
        scopes: [String],
        conditions: [Condition],
        conditionDisplayByKey: [String: ConditionDisplayState],
        includeSubfolders: Bool = true,
        includeDirectories: Bool = false,
    ) {
        self.init(
            scopeSelection: ComposerScopeSelection.fromLegacyScopes(scopes),
            conditions: conditions,
            conditionDisplayByKey: conditionDisplayByKey,
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

@ObservableState
public struct ComposerState: Equatable {
    public var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    public var operatorPicker: OperatorPickerFeature.State = .init()
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
    public var scopes: [String] {
        get { scopeEditor.selection.legacyScopePaths }
        set { scopeEditor.selection = ComposerScopeSelection.fromLegacyScopes(newValue) }
    }

    public var conditions: [Condition] = []
    public var conditionDisplayByKey: [String: ConditionDisplayState] = [:]
    public var operatorOptionsByKey: [String: [String]] = [:]
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

    public var lastSearchResponse: VoyagerShared.SearchResponsePayload?
    public var lastFiltersResponse: VoyagerShared.SearchResponsePayload?
    public var searchStartedAt: Date?
    public var filtersStartedAt: Date?
    var activeFiltersMetricSource: String?
    public var hasSubmittedInSession: Bool = false

    public init() {}

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

    public var isSemanticallyRootOnly: Bool {
        scopeEditor.selection.isRootOnly
    }

    var scopeSummary: ComposerScopeSummary {
        scopeEditor.summary
    }

    public var shouldAutoApplyScopeChange: Bool {
        hasCommittedQuerySearch
            || hasCommittedScopeSearch
            || conditions.contains(where: \.isSearchReady)
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
                conditions: conditions,
                conditionDisplayByKey: conditionDisplayByKey,
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

    public mutating func applyCollectionDraftRestorePayload(_ payload: CollectionDraftRestorePayload) {
        let trimmedQuery = payload.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        if payload.openedURL == nil {
            text = payload.context.query
        } else {
            text = ""
        }
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.context.scopes,
            exceptions: payload.context.excludedScopes,
            includeSubfolders: payload.context.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.context.includeSubfolders
        includeDirectories = payload.context.includeDirectories
        conditions = payload.context.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    public mutating func applyCollectionNavigationComposerPayload(_ payload: CollectionNavigationStatePayload) {
        let trimmedQuery = payload.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        text = payload.composerText
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.scopes,
            exceptions: payload.excludedScopes,
            includeSubfolders: payload.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.includeSubfolders
        includeDirectories = payload.includeDirectories
        conditions = payload.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    public mutating func applyCollectionOpenRestorationComposerPayload(
        _ payload: CollectionOpenRestorationPayload,
        registryClient: RegistryClient,
    ) {
        pendingSearchQuery = payload.context.query.isEmpty ? nil : payload.context.query
        text = payload.context.query
        let selection = ComposerScopeSelection.fromCanonicalScopes(
            bases: payload.context.scopes,
            exceptions: payload.context.excludedScopes,
            includeSubfolders: payload.context.includeSubfolders,
        )
        scopeEditor.selection = selection
        scopeEditor.includeSubfolders = payload.context.includeSubfolders
        includeDirectories = payload.context.includeDirectories
        conditions = payload.context.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
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
        )
        lastFiltersResponse = nil
        lastSearchResponse = nil
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

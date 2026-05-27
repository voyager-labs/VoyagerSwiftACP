import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesCollection
import VoyagerShared

private let kComposerLogger = Logger(label: "Voyager")

public enum ComposerQueryRenderPhase: Equatable, Sendable {
    case idle
    case searching
    case chipsAppliedPendingList
    case listApplied
    case failed
}

enum ComposerQueryPhaseTransition: Sendable {
    case reset
    case startSearch
    case searchSucceeded
    case searchFailed
    case listApplied
}

@Reducer
public struct ComposerFeature {
    public typealias State = ComposerState
    public typealias Action = ComposerAction

    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    public nonisolated enum CancelID: Hashable, Sendable {
        case search
        case filters
        case scopeEditorSearch
        case feedbackDismiss
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        ComposerSearchLifecycleReducer()
        ComposerHistoryReducer()
        ComposerConditionEditingReducer()
        ComposerScopeReducer()
        ComposerSaveReducer()

        Scope(state: \.propertyPicker, action: \.propertyPicker) {
            ConditionPropertyPickerFeature()
        }
        Scope(state: \.operatorPicker, action: \.operatorPicker) {
            OperatorPickerFeature()
        }
        Scope(state: \.valuePicker, action: \.valuePicker) {
            ValuePickerFeature()
        }

        Reduce { state, action in
            switch action {
            case let .view(.setPresented(isPresented)):
                return handleSetPresented(state: &state, isPresented: isPresented)

            case let .view(.setText(text)):
                state.text = text
                state.transientFeedback = nil
                return .cancel(id: CancelID.feedbackDismiss)

            case .view(.focusQueryField):
                state.focusRequestID += 1
                return .none

            case .view(.scopeFeedbackUndoTapped):
                return .send(.view(.undo))

            case .view(.scopeFeedbackRedoTapped):
                return .send(.view(.redo))

            case .view(.undo),
                 .view(.redo):
                return .none

            case let .internal(.dismissTransientFeedback(id)):
                if state.transientFeedback?.id == id {
                    state.transientFeedback = nil
                }
                return .none

            case .view(.submit),
                 .view(.cancelSearch),
                 .view(.cancelFilters):
                state.transientFeedback = nil
                return .cancel(id: CancelID.feedbackDismiss)

            case let .internal(.applyCollectionDraftRestore(payload)):
                state.applyCollectionDraftRestorePayload(payload)
                return .none

            case let .internal(.applyCollectionNavigationComposer(payload)):
                state.applyCollectionNavigationComposerPayload(payload)
                return .none

            case let .internal(.syncCollectionState(context, url, compatibility, isCollectionMode)):
                state.collectionContext = context
                state.openedCollectionURL = url
                state.openedCollectionCompatibility = compatibility
                state.isCollectionMode = isCollectionMode
                return .none

            case let .internal(.updateLastFiltersResponse(response)):
                state.lastFiltersResponse = response
                return .none

            case .internal(.clearPendingSearchQuery):
                state.pendingSearchQuery = nil
                return .none

            case let .internal(.setPendingSearchQuery(query)):
                state.pendingSearchQuery = query
                return .none

            case let .internal(.setLoadingFilters(isLoading)):
                state.isLoadingFilters = isLoading
                return .none

            case let .internal(.setInitialScope(path)):
                state.scopes = [path]
                return .none

            case let .internal(.resetComposerAndSync(context, url, compatibility, isCollectionMode)):
                state = .init()
                state.collectionContext = context
                state.openedCollectionURL = url
                state.openedCollectionCompatibility = compatibility
                state.isCollectionMode = isCollectionMode
                return .none

            case .view(.applyFilters),
                 .view(.setDisplayUnit),
                 .view(.addCondition),
                 .view(.removeCondition),
                 .view(.setOperator),
                 .view(.replaceConditionProperty),
                 .view(.setValue),
                 .view(.candidateScope),
                 .view(.currentScope),
                 .view(.clearAll),
                 .view(.saveCollection),
                 .view(.saveCollectionAs),
                 .view(.scopeEditorOpen),
                 .view(.scopeEditorSetPresented),
                 .view(.scopeEditorSetIncludeSubfolders),
                 .view(.scopeEditorSetQueryText),
                 .view(.exceptionScope),
                 .propertyPicker,
                 .operatorPicker,
                 .valuePicker,
                 .internal(.searchResponse),
                 .internal(.filtersResponse),
                 .internal(.scopeEditorSeedCurrentPath),
                 .internal(.scopeEditorSearchResponse),
                 .internal(.searchListApplied),
                 .delegate:
                return .none
            }
        }
    }
}

private func handleSetPresented(
    state: inout ComposerFeature.State,
    isPresented: Bool
) -> Effect<ComposerFeature.Action> {
    state.isPresented = isPresented
    if !isPresented {
        let shouldPreserveFilterLifecycle = state.scopeEditor.isPresented
            && state.scopeEditor.hasPendingScopeRuleChanges
            && state.shouldAutoApplyScopeChange
        let hasActiveFilterLifecycle = state.isFilteringInFlight
            || state.activeFiltersRequestID != nil
            || state.isLoadingFilters
        let shouldKeepFiltersAlive = shouldPreserveFilterLifecycle || hasActiveFilterLifecycle
        let shouldCloseScopeEditorWithoutCommit = state.scopeEditor.isPresented && !shouldPreserveFilterLifecycle

        state.hasSubmittedInSession = false
        state.searchStartedAt = nil
        state.transientFeedback = nil
        state.isLoadingSearch = false
        state.activeSearchRequestID = nil
        state.lastAcceptedSearchRequestID = nil
        applyQueryPhaseTransition(.reset, state: &state)

        if !shouldKeepFiltersAlive {
            state.filtersStartedAt = nil
            state.submittedSearchFilters = nil
            state.isLoadingFilters = false
            state.isFilteringInFlight = false
            state.activeFiltersRequestID = nil
            state.lastAcceptedFiltersRequestID = nil
            state.lastScopeChangeFeedback = nil
        }

        var effects: [Effect<ComposerFeature.Action>] = [
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.feedbackDismiss),
        ]
        if shouldPreserveFilterLifecycle {
            effects.append(.send(.scopeEditorSetPresented(false)))
        }
        if shouldCloseScopeEditorWithoutCommit {
            state.scopeEditor.isPresented = false
            state.resetScopeEditorInteractionState(clearQuery: true)
        }
        if !shouldKeepFiltersAlive {
            effects.append(.cancel(id: ComposerFeature.CancelID.filters))
        }

        return .merge(effects)
    }

    return .none
}

func applyQueryPhaseTransition(
    _ transition: ComposerQueryPhaseTransition,
    state: inout ComposerFeature.State
) {
    switch transition {
    case .reset:
        state.queryRenderPhase = .idle
    case .startSearch:
        state.queryRenderPhase = .searching
    case .searchSucceeded:
        state.queryRenderPhase = .chipsAppliedPendingList
    case .searchFailed:
        state.queryRenderPhase = .failed
    case .listApplied:
        if state.queryRenderPhase == .chipsAppliedPendingList {
            state.queryRenderPhase = .listApplied
        }
    }
}

func applyAppliedFilters(
    _ appliedFilters: VoyagerShared.AppliedFiltersPayload?,
    state: inout ComposerFeature.State,
    registryClient: RegistryClient
) {
    if let includeSubfolders = appliedFilters?.includeSubfolders {
        state.scopeEditor.includeSubfolders = includeSubfolders
    }
    let previousDisplayByKey = state.conditionDisplayByKey
    let resolved = AppliedFiltersUtils.resolveDetailed(
        appliedFilters,
        fallbackScopes: state.scopeEditor.selection.legacyScopePaths,
        fallbackConditions: state.conditions,
        registryClient: registryClient,
        fallbackExcludedScopes: state.scopeEditor.selection.exceptions.map(\.path),
    )
    let selection = ComposerScopeSelection.fromCanonicalScopes(
        bases: resolved.scopes,
        exceptions: resolved.excludedScopes,
        includeSubfolders: state.scopeEditor.includeSubfolders,
    )
    let shouldPreserveLocalMultiScope = state.scopeEditor.selection.explicitBases.count > 1
        && resolved.excludedScopes.isEmpty
        && selection.legacyScopePaths != state.scopeEditor.selection.legacyScopePaths
    if !shouldPreserveLocalMultiScope {
        state.scopeEditor.selection = selection
    }
    state.conditions = resolved.conditions
    state.conditionDisplayByKey = Dictionary(
        uniqueKeysWithValues: resolved.conditions.compactMap { condition in
            let displayState: ConditionDisplayState? = if let previous = previousDisplayByKey[condition.propertyKey] {
                reconcileDisplayState(
                    for: condition,
                    previous: previous,
                    registryClient: registryClient
                )
            } else {
                defaultDisplayState(for: condition, registryClient: registryClient)
            }
            guard let displayState else { return nil }
            return (condition.propertyKey, displayState)
        }
    )
    updateOperatorOptions(state: &state, registryClient: registryClient)
}

func defaultDisplayState(
    for condition: Condition,
    registryClient: RegistryClient
) -> ConditionDisplayState? {
    guard condition.valueType == "number",
          let spec = UnitValueUtils.spec(for: condition.propertyKey, registryClient: registryClient)
    else {
        return nil
    }

    let unitValueState = UnitValuePresentationUtils.makeState(spec: spec)
    let unitCode = unitValueState.selectedUnitCode
    let displayValues = (condition.values ?? []).map { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return UnitValueUtils.fromCanonical(canonicalText: trimmed, to: unitCode, spec: spec) ?? trimmed
    }

    return .init(values: displayValues, unitValueState: unitValueState)
}

private func reconcileDisplayState(
    for condition: Condition,
    previous: ConditionDisplayState,
    registryClient: RegistryClient
) -> ConditionDisplayState? {
    guard let previousUnitValueState = previous.unitValueState,
          let spec = UnitValueUtils.spec(for: condition.propertyKey, registryClient: registryClient),
          UnitValueUtils.unitCodes(spec: spec).contains(previousUnitValueState.selectedUnitCode)
    else {
        return defaultDisplayState(for: condition, registryClient: registryClient)
    }
    let values = condition.values ?? []
    let unitCode = previousUnitValueState.selectedUnitCode

    let displayValues = values.map { value -> String in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return UnitValueUtils.fromCanonical(canonicalText: trimmed, to: unitCode, spec: spec) ?? trimmed
    }

    return .init(
        values: displayValues,
        unitValueState: UnitValuePresentationUtils.makeState(spec: spec, preferredUnitCode: unitCode)
    )
}

func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker = .init()
}

func applyFiltersIfNeeded(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    requestID: UUID = UUID()
) -> Effect<ComposerFeature.Action> {
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    state.activeFiltersRequestID = requestID
    let filters = buildFilters(from: state)
    guard !filters.scopes.isEmpty || !filters.conditions.isEmpty else {
        state.isLoadingFilters = false
        state.isFilteringInFlight = false
        state.activeFiltersRequestID = nil
        state.pendingSearchQuery = nil
        return .cancel(id: ComposerFeature.CancelID.filters)
    }
    state.markScopeChangeFeedbackPending(.filters(requestID))
    return .run { send in
        do {
            let response = try await searchClient.applyFilters(.init(filters: filters))
            await send(.filtersResponse(requestID, .success(response)))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            await send(.filtersResponse(requestID, .failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.filters, cancelInFlight: true)
}

func buildFilters(from state: ComposerFeature.State) -> VoyagerShared.SearchFiltersPayload {
    let conditionPayloads: [VoyagerShared.SearchConditionPayload] = state.conditions
        .compactMap { condition -> VoyagerShared.SearchConditionPayload? in
            guard condition.isSearchReady else { return nil }
            guard let op = condition.operatorCode else { return nil }
            if let arity = condition.operatorValueArity, arity == 0 {
                return VoyagerShared.SearchConditionPayload(
                    propertyKey: condition.propertyKey,
                    operator: op,
                    value: nil
                )
            }
            guard let values = condition.values, !values.isEmpty else { return nil }
            guard let encoded = ConditionValueEncoder.encode(condition: condition, values: values) else { return nil }
            return VoyagerShared.SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: op,
                value: encoded
            )
        }
    kComposerLogger.debug(
        "Built search filters payload",
        metadata: [
            "scopes": .stringConvertible(state.scopeEditor.selection.legacyScopePaths.count),
            "conditions": .stringConvertible(conditionPayloads.count),
        ]
    )
    return VoyagerShared.SearchFiltersPayload(
        scopes: state.scopeEditor.selection.legacyScopePaths,
        excludedScopes: state.scopeEditor.selection.exceptions.map(\.path),
        includeSubfolders: state.scopeEditor.effectiveIncludeSubfolders,
        conditions: conditionPayloads,
    )
}

func updateOperatorOptions(
    state: inout ComposerFeature.State,
    registryClient: RegistryClient
) {
    state.operatorOptionsByKey = Dictionary(
        uniqueKeysWithValues: state.conditions.map {
            ($0.propertyKey, registryClient.operatorCodes(for: $0.propertyKey))
        }
    )
}

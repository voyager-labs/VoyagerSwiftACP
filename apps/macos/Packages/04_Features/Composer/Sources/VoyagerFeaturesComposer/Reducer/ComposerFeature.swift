// swiftformat:disable modifierOrder
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

enum ComposerQueryPhaseTransition {
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
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.continuousClock)
    var continuousClock
    @Dependency(\.composerMetricClient)
    var composerMetricClient

    nonisolated enum CancelID: Hashable {
        case search(ownerID: UUID?)
        case filters(ownerID: UUID?)
        case scopeEditorSearch
        case feedbackDismiss(ownerID: UUID?)
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
        Scope(state: \.valuePicker, action: \.valuePicker) {
            ValuePickerFeature()
        }
        .forEach(\.conditionEditors, action: \.conditionEditor) {
            ConditionEditorFeature()
        }

        Reduce { state, action in
            switch action {
            case let .view(.setPresented(isPresented)):
                return handleSetPresented(
                    state: &state,
                    isPresented: isPresented,
                    composerMetricClient: composerMetricClient,
                )

            case let .view(.setText(text)):
                state.text = text
                state.transientFeedback = nil
                return .cancel(id: CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID))

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

            case let .internal(.presentTransientFeedback(feedback)):
                state.transientFeedback = feedback
                let clock = continuousClock
                let feedbackDismissID = CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID)
                return .concatenate(
                    .cancel(id: feedbackDismissID),
                    .run { [feedbackID = feedback.id] send in
                        try await clock.sleep(for: .seconds(4))
                        await send(.internal(.dismissTransientFeedback(feedbackID)))
                    }
                    .cancellable(id: feedbackDismissID, cancelInFlight: true),
                )

            case .internal(.clearTransientFeedback):
                state.transientFeedback = nil
                return .cancel(id: CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID))

            case .internal(.cleanupCollectionWork):
                let searchCancellation = handleCancelSearch(
                    state: &state,
                    composerMetricClient: composerMetricClient,
                )
                let filtersCancellation = handleCancelFilters(
                    state: &state,
                    composerMetricClient: composerMetricClient,
                )
                state.transientFeedback = nil
                state.isLoadingSearch = false
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                state.activeSearchRequestID = nil
                state.activeFiltersRequestID = nil
                state.lastAcceptedSearchRequestID = nil
                state.lastAcceptedFiltersRequestID = nil
                state.pendingSearchQuery = nil
                state.searchStartedAt = nil
                state.filtersStartedAt = nil
                state.activeFiltersMetricSource = nil
                applyQueryPhaseTransition(.reset, state: &state)
                return .merge(
                    searchCancellation,
                    filtersCancellation,
                    .cancel(id: CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID)),
                )

            case .view(.submit),
                 .view(.cancelSearch),
                 .view(.cancelFilters):
                state.transientFeedback = nil
                return .cancel(id: CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID))

            case let .internal(.applyCollectionDraftRestore(payload)):
                state.applyCollectionDraftRestorePayload(payload, uuid: { uuid() })
                return .none

            case let .internal(.applyCollectionNavigationComposer(payload)):
                state.applyCollectionNavigationComposerPayload(payload, uuid: { uuid() })
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
                let cancellationOwnerID = state.cancellationOwnerID
                state = .init()
                state.cancellationOwnerID = cancellationOwnerID
                state.collectionContext = context
                state.openedCollectionURL = url
                state.openedCollectionCompatibility = compatibility
                state.isCollectionMode = isCollectionMode
                return .none

            case .view(.applyFilters),
                 .view(.addCondition),
                 .view(.removeCondition),
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
                 .valuePicker,
                 .conditionEditor,
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
    isPresented: Bool,
    composerMetricClient: ComposerMetricClient,
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
        let searchCancellation = handleCancelSearch(
            state: &state,
            composerMetricClient: composerMetricClient,
        )

        state.hasSubmittedInSession = false
        state.transientFeedback = nil
        state.lastAcceptedSearchRequestID = nil

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
            searchCancellation,
            .cancel(id: ComposerFeature.CancelID.feedbackDismiss(ownerID: state.cancellationOwnerID)),
        ]
        if shouldPreserveFilterLifecycle {
            effects.append(.send(.scopeEditorSetPresented(false)))
        }
        if shouldCloseScopeEditorWithoutCommit {
            state.scopeEditor.isPresented = false
            state.resetScopeEditorInteractionState(clearQuery: true)
        }
        if !shouldKeepFiltersAlive {
            effects.append(.cancel(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID)))
        }

        return .merge(effects)
    }

    return .none
}

func applyQueryPhaseTransition(
    _ transition: ComposerQueryPhaseTransition,
    state: inout ComposerFeature.State,
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
    registryClient: RegistryClient,
    uuid: () -> UUID = UUID.init,
) {
    if let includeSubfolders = appliedFilters?.includeSubfolders {
        state.scopeEditor.includeSubfolders = includeSubfolders
    }
    let resolved = AppliedFilterResolver.resolveDetailed(
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
    applyResolvedConditions(
        resolved.conditions,
        state: &state,
        registryClient: registryClient,
        uuid: uuid,
    )
}

private func applyResolvedConditions(
    _ conditions: [Condition],
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
    uuid: () -> UUID,
) {
    let previousEditorsByKey = Dictionary(uniqueKeysWithValues: state.conditionEditors.map {
        ($0.condition.property.key, $0)
    })
    let canonicalKeys = conditions.map(\.property.key)
    guard Set(canonicalKeys).count == canonicalKeys.count else {
        state.transientFeedback = .init(
            id: UUID(),
            kind: .error,
            message: "Duplicate filter properties were returned.",
            stage: .queryExecution,
            category: .executionFailure,
        )
        return
    }
    state.conditionEditors = IdentifiedArray(uniqueElements: conditions.map { condition in
        let displayState: ConditionDisplayState? = if let previous = previousEditorsByKey[condition.property.key]?
            .displayState
        {
            reconcileDisplayState(
                for: condition,
                previous: previous,
                registryClient: registryClient,
            )
        } else {
            defaultDisplayState(for: condition, registryClient: registryClient)
        }
        return .init(
            id: previousEditorsByKey[condition.property.key]?.id ?? uuid(),
            condition: condition,
            displayState: displayState,
        )
    })
}

func defaultDisplayState(
    for condition: Condition,
    registryClient _: RegistryClient,
) -> ConditionDisplayState? {
    guard let unitContract = condition.property.unitContract else { return nil }
    let unitValueState = UnitValueState(contract: unitContract)
    let canonicalValues = condition.values ?? []
    let displayValues = canonicalValues.compactMap {
        ConditionUnitConverter.fromCanonical(
            canonicalText: $0,
            to: unitValueState.selectedUnitCode,
            contract: unitContract,
        )
    }
    guard displayValues.count == canonicalValues.count else { return nil }
    return ConditionDisplayState(values: displayValues, unitValueState: unitValueState)
}

private func reconcileDisplayState(
    for condition: Condition,
    previous: ConditionDisplayState,
    registryClient: RegistryClient,
) -> ConditionDisplayState? {
    guard let unitContract = condition.property.unitContract else {
        return ConditionDisplayState(values: condition.values ?? [], unitValueState: previous.unitValueState)
    }
    guard let unitValueState = previous.unitValueState,
          ConditionUnitConverter.unitCodes(contract: unitContract).contains(unitValueState.selectedUnitCode)
    else {
        return defaultDisplayState(for: condition, registryClient: registryClient)
    }
    let canonicalValues = condition.values ?? []
    let displayValues = canonicalValues.compactMap {
        ConditionUnitConverter.fromCanonical(
            canonicalText: $0,
            to: unitValueState.selectedUnitCode,
            contract: unitContract,
        )
    }
    guard displayValues.count == canonicalValues.count else {
        return defaultDisplayState(for: condition, registryClient: registryClient)
    }
    return ConditionDisplayState(values: displayValues, unitValueState: unitValueState)
}

func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker = .init()
}

func applyFiltersIfNeeded(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    requestID: UUID = UUID(),
    metricSource: String = ComposerCollectionFilterMetrics.sourceManualApply,
) -> Effect<ComposerFeature.Action> {
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    state.activeFiltersRequestID = requestID
    state.activeFiltersMetricSource = metricSource
    let filters = buildFilters(from: state)
    guard !filters.conditions.isEmpty else {
        state.isLoadingFilters = false
        state.isFilteringInFlight = false
        state.activeFiltersRequestID = nil
        state.activeFiltersMetricSource = nil
        state.pendingSearchQuery = nil
        return .cancel(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID))
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
    .cancellable(id: ComposerFeature.CancelID.filters(ownerID: state.cancellationOwnerID), cancelInFlight: true)
}

func buildFilters(from state: ComposerFeature.State) -> VoyagerShared.SearchFiltersPayload {
    let conditionPayloads: [VoyagerShared.SearchConditionPayload] = state.conditions
        .compactMap { condition -> VoyagerShared.SearchConditionPayload? in
            guard condition.isExecutionReady, let operation = condition.operation else { return nil }
            if case .fixed(0) = operation.valueContract.count {
                return VoyagerShared.SearchConditionPayload(
                    propertyKey: condition.property.key,
                    operator: operation.code,
                    value: nil,
                )
            }
            guard let values = condition.values, !values.isEmpty else { return nil }
            guard let encoded = ConditionCodec.encode(condition: condition) else { return nil }
            return VoyagerShared.SearchConditionPayload(
                propertyKey: condition.property.key,
                operator: operation.code,
                value: encoded,
            )
        }
    kComposerLogger.debug(
        "Built search filters payload",
        metadata: [
            "scopes": .stringConvertible(state.scopeEditor.selection.legacyScopePaths.count),
            "conditions": .stringConvertible(conditionPayloads.count),
        ],
    )
    return VoyagerShared.SearchFiltersPayload(
        scopes: state.scopeEditor.selection.legacyScopePaths,
        excludedScopes: state.scopeEditor.selection.exceptions.map(\.path),
        includeSubfolders: state.scopeEditor.effectiveIncludeSubfolders,
        conditions: conditionPayloads,
    )
}

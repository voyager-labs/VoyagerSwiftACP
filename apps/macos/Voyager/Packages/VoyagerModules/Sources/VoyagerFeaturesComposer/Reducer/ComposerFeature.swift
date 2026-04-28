import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesEntry
import VoyagerShared

private let kComposerLogger = Logger(label: "Voyager")

public enum ComposerQueryRenderPhase: Equatable, Sendable {
    case idle
    case searching
    case chipsAppliedPendingList
    case listApplied
    case failed
}

public enum ComposerQueryPhaseTransition: Sendable {
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

    public init() {}

    @Dependency(\.searchClient)
    public var searchClient
    @Dependency(\.registryClient)
    public var registryClient

    public nonisolated enum CancelID: Hashable, Sendable {
        case search
        case filters
        case feedbackDismiss
    }

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

            case .view(.applyFilters),
                 .view(.setDisplayUnit),
                 .view(.addCondition),
                 .view(.removeCondition),
                 .view(.setOperator),
                 .view(.replaceConditionProperty),
                 .view(.setValue),
                 .view(.addScope),
                 .view(.removeScope),
                 .view(.updateScope),
                 .view(.clearAll),
                 .view(.saveCollection),
                 .view(.saveCollectionAs),
                 .propertyPicker,
                 .operatorPicker,
                 .valuePicker,
                 .internal(.searchResponse),
                 .internal(.filtersResponse),
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
) -> Effect<ComposerFeature.Action> {
    state.isPresented = isPresented
    if !isPresented {
        state.hasSubmittedInSession = false
        state.searchStartedAt = nil
        state.filtersStartedAt = nil
        state.transientFeedback = nil
        state.submittedSearchFilters = nil
        state.isLoadingSearch = false
        state.isLoadingFilters = false
        state.isFilteringInFlight = false
        state.activeSearchRequestID = nil
        state.activeFiltersRequestID = nil
        state.lastAcceptedSearchRequestID = nil
        state.lastAcceptedFiltersRequestID = nil
        applyQueryPhaseTransition(.reset, state: &state)

        return .merge(
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
            .cancel(id: ComposerFeature.CancelID.feedbackDismiss),
        )
    }

    return .none
}

public func applyQueryPhaseTransition(
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

public func applyAppliedFilters(
    _ appliedFilters: VoyagerShared.AppliedFiltersPayload?,
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    let previousDisplayByKey = state.conditionDisplayByKey
    let resolved = AppliedFiltersUtils.resolve(
        appliedFilters,
        fallbackScopes: state.scopes,
        fallbackConditions: state.conditions,
        registryClient: registryClient,
    )
    state.scopes = resolved.scopes
    state.conditions = resolved.conditions
    state.conditionDisplayByKey = Dictionary(
        uniqueKeysWithValues: resolved.conditions.compactMap { condition in
            let displayState: ConditionDisplayState? = if let previous = previousDisplayByKey[condition.propertyKey] {
                reconcileDisplayState(
                    for: condition,
                    previous: previous,
                    registryClient: registryClient,
                )
            } else {
                defaultDisplayState(for: condition, registryClient: registryClient)
            }
            guard let displayState else { return nil }
            return (condition.propertyKey, displayState)
        },
    )
    updateOperatorOptions(state: &state, registryClient: registryClient)
}

public func defaultDisplayState(
    for condition: Condition,
    registryClient: RegistryClient,
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
    registryClient: RegistryClient,
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
        unitValueState: UnitValuePresentationUtils.makeState(spec: spec, preferredUnitCode: unitCode),
    )
}

public func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker = .init()
}

public func applyFiltersIfNeeded(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
    requestID: UUID = UUID(),
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
}

public func buildFilters(from state: ComposerFeature.State) -> VoyagerShared.SearchFiltersPayload {
    let conditionPayloads: [VoyagerShared.SearchConditionPayload] = state.conditions
        .compactMap { condition -> VoyagerShared.SearchConditionPayload? in
            guard condition.isActive else { return nil }
            guard let op = condition.operatorCode else { return nil }
            if let arity = condition.operatorValueArity, arity == 0 {
                return VoyagerShared.SearchConditionPayload(
                    propertyKey: condition.propertyKey,
                    operator: op,
                    value: nil,
                )
            }
            guard let values = condition.values, !values.isEmpty else { return nil }
            guard let encoded = ConditionValueEncoder.encode(condition: condition, values: values) else { return nil }
            return VoyagerShared.SearchConditionPayload(
                propertyKey: condition.propertyKey,
                operator: op,
                value: encoded,
            )
        }
    kComposerLogger.debug(
        "Built search filters payload",
        metadata: [
            "scopes": .stringConvertible(state.scopes.count),
            "conditions": .stringConvertible(conditionPayloads.count),
        ],
    )
    return VoyagerShared.SearchFiltersPayload(
        scopes: state.scopes,
        conditions: conditionPayloads,
    )
}

public func updateOperatorOptions(
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    state.operatorOptionsByKey = Dictionary(
        uniqueKeysWithValues: state.conditions.map {
            ($0.propertyKey, registryClient.operatorCodes(for: $0.propertyKey))
        },
    )
}

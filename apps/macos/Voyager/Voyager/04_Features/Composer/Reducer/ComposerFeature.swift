import ComposableArchitecture
import Foundation
import Logging

private let kComposerLogger = Logger(label: "Voyager")

enum ComposerQueryRenderPhase: Equatable, Sendable {
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
struct ComposerFeature {
    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    typealias State = ComposerState
    typealias Action = ComposerAction

    nonisolated enum CancelID: Hashable, Sendable {
        case search
        case filters
    }

    var body: some Reducer<State, Action> {
        ComposerSearchLifecycleReducer()
        ComposerHistoryReducer()
        ComposerConditionEditingReducer()
        ComposerScopeReducer()
        ComposerSaveReducer()

        Scope(state: \.collection, action: \.collection) {
            CollectionFeature()
        }
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
                handleSetPresented(state: &state, isPresented: isPresented)
                return .none

            case let .view(.setText(text)):
                state.text = text
                return .none

            case .view(.focusQueryField):
                state.focusRequestID += 1
                return .none

            case .view(.undo),
                 .view(.redo):
                return .none

            case .view(.submit),
                 .view(.cancelSearch),
                 .view(.cancelFilters),
                 .view(.applyFilters),
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
                 .collection,
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

private func handleSetPresented(state: inout ComposerFeature.State, isPresented: Bool) {
    state.isPresented = isPresented
    if !isPresented {
        state.hasSubmittedInSession = false
        state.searchStartedAt = nil
        state.filtersStartedAt = nil
        applyQueryPhaseTransition(.reset, state: &state)
    }
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
    _ appliedFilters: AppliedFiltersPayload?,
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
            guard let previous = previousDisplayByKey[condition.propertyKey],
                  let reconciled = reconcileDisplayState(for: condition, previous: previous)
            else {
                return nil
            }
            return (condition.propertyKey, reconciled)
        },
    )
    updateOperatorOptions(state: &state, registryClient: registryClient)
}

private func reconcileDisplayState(
    for condition: Condition,
    previous: ConditionDisplayState,
) -> ConditionDisplayState? {
    guard let unitCode = previous.unitCode,
          let spec = UnitValueUtils.spec(for: condition.propertyKey),
          UnitValueUtils.unitCodes(spec: spec).contains(unitCode),
          let values = condition.values
    else {
        return nil
    }

    let displayValues = values.map { value -> String in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return UnitValueUtils.fromCanonical(canonicalText: trimmed, to: unitCode, spec: spec) ?? trimmed
    }

    return .init(values: displayValues, unitCode: unitCode)
}

func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker = .init()
}

func applyFiltersIfNeeded(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    let filters = buildFilters(from: state)
    guard !filters.conditions.isEmpty else {
        state.isLoadingFilters = false
        state.isFilteringInFlight = false
        return .cancel(id: ComposerFeature.CancelID.filters)
    }
    return .run { send in
        do {
            let response = try await searchClient.applyFilters(.init(filters: filters))
            await send(.filtersResponse(.success(response)))
        } catch {
            await send(.filtersResponse(.failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.filters, cancelInFlight: true)
}

func buildFilters(from state: ComposerFeature.State) -> SearchFiltersPayload {
    let conditionPayloads: [SearchConditionPayload] = state.conditions.compactMap { condition in
        guard condition.isActive else { return nil }
        guard let op = condition.operatorCode else { return nil }
        if let arity = condition.operatorValueArity, arity == 0 {
            return SearchConditionPayload(propertyKey: condition.propertyKey, operator: op, value: nil)
        }
        guard let values = condition.values, !values.isEmpty else { return nil }
        guard let encoded = ConditionValueEncoder.encode(condition: condition, values: values) else { return nil }
        return SearchConditionPayload(propertyKey: condition.propertyKey, operator: op, value: encoded)
    }
    kComposerLogger.debug(
        "Built search filters payload",
        metadata: [
            "scopes": .stringConvertible(state.scopes.count),
            "conditions": .stringConvertible(conditionPayloads.count),
        ],
    )
    return SearchFiltersPayload(
        scopes: state.scopes,
        conditions: conditionPayloads,
    )
}

func updateOperatorOptions(
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    state.operatorOptionsByKey = Dictionary(
        uniqueKeysWithValues: state.conditions.map {
            ($0.propertyKey, registryClient.operatorCodes(for: $0.propertyKey))
        },
    )
}

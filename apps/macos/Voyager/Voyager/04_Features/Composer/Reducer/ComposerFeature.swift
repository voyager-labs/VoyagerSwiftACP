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

func handleAddScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    guard !state.scopes.contains(path) else { return .none }
    state.pushHistory()
    if state.scopes.isEmpty || state.scopes == [ComposerScopeUtils.rootScopePath] {
        state.scopes = [path]
    } else {
        state.scopes.append(path)
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

func handleRemoveScope(
    state: inout ComposerFeature.State,
    path: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if state.scopes.contains(path) {
        state.pushHistory()
        state.scopes.removeAll { $0 == path }
        if state.scopes.isEmpty {
            state.scopes = [ComposerScopeUtils.rootScopePath]
        }
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

func handleUpdateScope(
    state: inout ComposerFeature.State,
    oldPath: String,
    newPath: String,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if let index = state.scopes.firstIndex(of: oldPath), oldPath != newPath {
        state.pushHistory()
        state.scopes[index] = newPath
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

func handleClearAll(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    state.pushHistory()
    state.text = ""
    state.scopes = [ComposerScopeUtils.rootScopePath]
    state.conditions = []
    state.operatorOptionsByKey = [:]
    state.propertyPicker = .init()
    state.operatorPicker = .init()
    state.valuePicker = .init()
    state.isLoadingFilters = false
    state.lastFiltersResponse = nil
    applyQueryPhaseTransition(.reset, state: &state)
    return .cancel(id: ComposerFeature.CancelID.filters)
}

func handleSubmit(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    let query = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .none }
    let filters = buildFilters(from: state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_composer_submit",
        value: 1,
    )
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_submit",
        value: 1,
    )
    if state.hasSubmittedInSession {
        VoyagerSentryMetricLogger.logMetric(
            "voyager_search_resubmit",
            value: 1,
        )
    }
    state.hasSubmittedInSession = true
    state.searchStartedAt = Date()
    state.isLoadingSearch = true
    state.isLoadingFilters = false
    state.lastFiltersResponse = nil
    applyQueryPhaseTransition(.startSearch, state: &state)
    state.text = ""

    let searchEffect: Effect<ComposerFeature.Action> = .run { send in
        do {
            let response = try await searchClient.search(
                .init(query: query, filters: filters),
            )
            await send(.searchResponse(.success(response)))
        } catch {
            await send(.searchResponse(.failure(error)))
        }
    }
    .cancellable(id: ComposerFeature.CancelID.search, cancelInFlight: true)

    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.filters),
        searchEffect,
    )
}

func handleCancelSearch(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    state.isLoadingSearch = false
    applyQueryPhaseTransition(.reset, state: &state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "search"],
    )
    return .cancel(id: ComposerFeature.CancelID.search)
}

func handleCancelFilters(state: inout ComposerFeature.State) -> Effect<ComposerFeature.Action> {
    state.isLoadingFilters = false
    state.isFilteringInFlight = false
    VoyagerSentryMetricLogger.logMetric(
        "voyager_search_cancel",
        value: 1,
        tags: ["type": "filters"],
    )
    return .cancel(id: ComposerFeature.CancelID.filters)
}

func handleApplyFilters(
    state: inout ComposerFeature.State,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    state.isLoadingSearch = false
    state.lastSearchResponse = nil
    state.isLoadingFilters = true
    state.isFilteringInFlight = true
    applyQueryPhaseTransition(.reset, state: &state)
    VoyagerSentryMetricLogger.logMetric(
        "voyager_composer_filters_apply",
        value: 1,
    )
    state.filtersStartedAt = Date()
    return .concatenate(
        .cancel(id: ComposerFeature.CancelID.search),
        applyFiltersIfNeeded(state: &state, searchClient: searchClient),
    )
}

func handleAddCondition(
    state: inout ComposerFeature.State,
    propertyKey: String,
    registryClient: RegistryClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let label = registryClient.labelForKey(propertyKey)
    let propertyType = registryClient.propertyTypeString(propertyKey)
    if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
        state.propertyPicker.duplicateMessage = "\"\(label)\" is already added."
        return .none
    }

    state.pushHistory()
    let condition = Condition(
        propertyKey: propertyKey,
        propertyLabel: label,
        propertyType: propertyType,
        operatorCode: nil,
        operatorLabel: nil,
        operatorValueArity: nil,
        operatorValueUIKind: nil,
        valueType: SystemPropertyTypeKey.normalizedValueType(from: propertyType),
        values: nil,
    )
    state.conditions.append(condition)
    updateOperatorOptions(state: &state, registryClient: registryClient)
    state.propertyPicker.duplicateMessage = nil
    state.propertyPicker.isPresented = false
    return .none
}

func handleRemoveCondition(
    state: inout ComposerFeature.State,
    propertyKey: String,
    registryClient: RegistryClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
        state.pushHistory()
        state.conditions.removeAll { $0.propertyKey == propertyKey }
        updateOperatorOptions(state: &state, registryClient: registryClient)
    }
    return .none
}

func handleSetOperator(
    state: inout ComposerFeature.State,
    propertyKey: String,
    operatorCode: String,
    registryClient: RegistryClient,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
        state.pushHistory()
        let propertyType = state.conditions[idx].propertyType
        let typeKey = SystemPropertyTypeKey.operatorKey(from: propertyType)
        let uiValueKind = registryClient.operatorUIKind(
            for: operatorCode,
            typeKey: typeKey,
        )
        state.conditions[idx].operatorCode = operatorCode
        state.conditions[idx].operatorLabel = registryClient.operatorLabel(for: operatorCode)
        let valueArity = registryClient.valueArity(for: uiValueKind)
        state.conditions[idx].operatorValueArity = valueArity
        state.conditions[idx].operatorValueUIKind = uiValueKind
        state.conditions[idx].valueType = registryClient.valueType(for: uiValueKind)
        state.conditions[idx].values = valueArity == 0 ? [] : nil

        if state.valuePicker.propertyKey == propertyKey {
            state.valuePicker.isPresented = false
            state.valuePicker.propertyKey = nil
            state.valuePicker.operatorCode = nil
            state.valuePicker.valueUIKind = "singleText"
            state.valuePicker.valueType = "string"
            state.valuePicker.values = Array(
                repeating: "",
                count: registryClient.valueArity(for: uiValueKind),
            )
            state.valuePicker.errorMessage = nil
        }

        if valueArity == 0 {
            return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
        }
    }
    return .none
}

func handleReplaceConditionProperty(
    state: inout ComposerFeature.State,
    originalKey: String,
    propertyKey: String,
    registryClient: RegistryClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    guard let idx = state.conditions.firstIndex(where: { $0.propertyKey == originalKey }) else {
        state.propertyPicker.editingConditionKey = nil
        state.propertyPicker.isPresented = false
        return .none
    }

    let label = registryClient.labelForKey(propertyKey)
    let propertyType = registryClient.propertyTypeString(propertyKey)

    if let dupIndex = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }), dupIndex != idx {
        state.propertyPicker.duplicateMessage = "\"\(label)\" is already added."
        return .none
    }

    state.pushHistory()
    state.conditions[idx].propertyKey = propertyKey
    state.conditions[idx].propertyLabel = label
    state.conditions[idx].propertyType = propertyType
    state.conditions[idx].operatorCode = nil
    state.conditions[idx].operatorLabel = nil
    state.conditions[idx].operatorValueArity = nil
    state.conditions[idx].operatorValueUIKind = nil
    state.conditions[idx].valueType = SystemPropertyTypeKey.normalizedValueType(from: propertyType)
    state.conditions[idx].values = nil
    updateOperatorOptions(state: &state, registryClient: registryClient)
    state.propertyPicker.editingConditionKey = nil
    state.propertyPicker.isPresented = false
    state.propertyPicker.duplicateMessage = nil
    return .none
}

func applyAppliedFilters(
    _ appliedFilters: AppliedFiltersPayload?,
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    let resolved = AppliedFiltersUtils.resolve(
        appliedFilters,
        fallbackScopes: state.scopes,
        fallbackConditions: state.conditions,
        registryClient: registryClient,
    )
    state.scopes = resolved.scopes
    state.conditions = resolved.conditions
    updateOperatorOptions(state: &state, registryClient: registryClient)
}

func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker.isPresented = false
    state.valuePicker.propertyKey = nil
    state.valuePicker.operatorCode = nil
    state.valuePicker.values = []
    state.valuePicker.errorMessage = nil
    state.valuePicker.editingIndex = nil
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

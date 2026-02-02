// swiftlint:disable file_length attributes
import ComposableArchitecture
import Foundation
import Logging

private let kComposerLogger = Logger(label: "Voyager")

@Reducer
// swiftlint:disable:next type_body_length
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
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    state.hasSubmittedInSession = false
                    state.searchStartedAt = nil
                    state.filtersStartedAt = nil
                }
                return .none

            case let .setText(text):
                state.text = text
                return .none

            case let .addScope(path):
                guard !state.isLoadingSearch else { return .none }
                guard !state.scopes.contains(path) else { return .none }
                state.pushHistory()
                if state.scopes.isEmpty || state.scopes == [ComposerScopeUtils.rootScopePath] {
                    state.scopes = [path]
                } else {
                    state.scopes.append(path)
                }
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case let .removeScope(path):
                guard !state.isLoadingSearch else { return .none }
                if state.scopes.contains(path) {
                    state.pushHistory()
                    state.scopes.removeAll { $0 == path }
                    if state.scopes.isEmpty {
                        state.scopes = [ComposerScopeUtils.rootScopePath]
                    }
                }
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case .clearAll:
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
                return .cancel(id: CancelID.filters)

            case .submit:
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
                state.text = ""
                let searchEffect: Effect<Action> = .run { send in
                    do {
                        let response = try await searchClient.search(
                            .init(query: query, filters: filters),
                        )
                        await send(.searchResponse(.success(response)))
                    } catch {
                        await send(.searchResponse(.failure(error)))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)
                return .concatenate(
                    .cancel(id: CancelID.filters),
                    searchEffect,
                )

            case .cancelSearch:
                state.isLoadingSearch = false
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_search_cancel",
                    value: 1,
                    tags: ["type": "search"],
                )
                return .cancel(id: CancelID.search)

            case .cancelFilters:
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_search_cancel",
                    value: 1,
                    tags: ["type": "filters"],
                )
                return .cancel(id: CancelID.filters)

            case .applyFilters:
                state.isLoadingSearch = false
                state.lastSearchResponse = nil
                state.isLoadingFilters = true
                state.isFilteringInFlight = true
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_composer_filters_apply",
                    value: 1,
                )
                state.filtersStartedAt = Date()
                return .concatenate(
                    .cancel(id: CancelID.search),
                    applyFiltersIfNeeded(state: &state, searchClient: searchClient),
                )

            case .saveCollection:
                let payload = SaveRequestPayload(
                    context: state.collectionContext,
                    sortKey: state.sortKey.rawValue,
                    sortOrder: state.sortOrder.rawValue,
                    viewLayout: state.viewLayout.rawValue,
                    isSearchLoading: state.isLoadingSearch,
                    isFiltersLoading: state.isLoadingFilters,
                )
                if let url = state.openedCollectionURL {
                    return .send(.collection(.saveToExisting(payload, url)))
                }
                return .send(.collection(.saveRequested(payload)))

            case .saveCollectionAs:
                let payload = SaveRequestPayload(
                    context: state.collectionContext,
                    sortKey: state.sortKey.rawValue,
                    sortOrder: state.sortOrder.rawValue,
                    viewLayout: state.viewLayout.rawValue,
                    isSearchLoading: state.isLoadingSearch,
                    isFiltersLoading: state.isLoadingFilters,
                )
                return .send(.collection(.saveRequested(payload)))

            case .focusQueryField:
                state.focusRequestID += 1
                return .none

            case let .updateScope(oldPath, newPath):
                guard !state.isLoadingSearch else { return .none }
                if let index = state.scopes.firstIndex(of: oldPath), oldPath != newPath {
                    state.pushHistory()
                    state.scopes[index] = newPath
                }
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case let .addCondition(propertyKey):
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

            case let .removeCondition(propertyKey):
                guard !state.isLoadingSearch else { return .none }
                if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions.removeAll { $0.propertyKey == propertyKey }
                    updateOperatorOptions(state: &state, registryClient: registryClient)
                }
                return .none

            case let .setOperator(propertyKey, operatorCode):
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

            case let .replaceConditionProperty(originalKey, propertyKey):
                guard !state.isLoadingSearch else { return .none }
                guard let idx = state.conditions.firstIndex(where: { $0.propertyKey == originalKey }) else {
                    state.propertyPicker.editingConditionKey = nil
                    state.propertyPicker.isPresented = false
                    return .none
                }

                let label = registryClient.labelForKey(propertyKey)
                let propertyType = registryClient.propertyTypeString(propertyKey)

                // 중복 방지: 다른 조건에 동일 key가 이미 있으면 안내 후 아무 변화 없이 종료
                if let dupIndex = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }),
                   dupIndex != idx
                {
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

            // TODO: UndoManager로 변경
            case .undo:
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let previous = state.history.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.redoHistory.append(current)
                state.scopes = previous.scopes
                state.conditions = previous.conditions
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            // TODO: UndoManager로 변경
            case .redo:
                guard !state.isLoadingSearch else { return .none }
                let before = buildFilters(from: state)
                guard let next = state.redoHistory.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.history.append(current)
                state.scopes = next.scopes
                state.conditions = next.conditions
                updateOperatorOptions(state: &state, registryClient: registryClient)
                let after = buildFilters(from: state)
                if before != after {
                    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
                }
                return .none

            case let .propertyPicker(.propertyTapped(property)):
                if let editingKey = state.propertyPicker.editingConditionKey {
                    return .send(.replaceConditionProperty(originalKey: editingKey, propertyKey: property))
                } else {
                    return .send(.addCondition(propertyKey: property))
                }

            case .collection:
                return .none

            case let .propertyPicker(.setPresented(isPresented)):
                if isPresented {
                    state.propertyPicker.existingKeys = Set(state.conditions.map(\.propertyKey))
                } else {
                    state.propertyPicker.existingKeys = []
                }
                return .none

            case let .propertyPicker(.startEditing(conditionKey)):
                state.propertyPicker.existingKeys = Set(
                    state.conditions
                        .map(\.propertyKey)
                        .filter { $0 != conditionKey },
                )
                return .none

            case .propertyPicker:
                return .none

            case let .operatorPicker(.setPresented(isPresented)):
                state.operatorPicker.isPresented = isPresented
                if !isPresented {
                    state.operatorPicker.propertyKey = nil
                    state.operatorPicker.options = []
                    state.operatorPicker.optionLabels = [:]
                }
                return .none

            case let .operatorPicker(.prepare(propertyKey, options, _)):
                guard !state.isLoadingSearch else { return .none }
                let optionLabels = Dictionary(
                    uniqueKeysWithValues: options.map { ($0, registryClient.operatorLabel(for: $0)) },
                )
                state.operatorPicker.propertyKey = propertyKey
                state.operatorPicker.options = options
                state.operatorPicker.optionLabels = optionLabels
                state.operatorPicker.isPresented = true
                return .none

            case let .operatorPicker(.select(option)):
                guard let propertyKey = state.operatorPicker.propertyKey else {
                    return .none
                }
                return .send(.setOperator(propertyKey: propertyKey, operatorCode: option))

            case .operatorPicker:
                return .none

            case let .valuePicker(.setPresented(isPresented)):
                if isPresented {
                    state.valuePicker.isPresented = true
                } else {
                    resetValuePicker(state: &state)
                }
                return .none

            case let .valuePicker(.prepare(payload)):
                guard !state.isLoadingSearch else { return .none }
                state.valuePicker.propertyKey = payload.propertyKey
                state.valuePicker.operatorCode = payload.operatorCode
                state.valuePicker.valueType = payload.valueType
                state.valuePicker.valueArity = max(0, payload.valueArity)
                state.valuePicker.valueUIKind = payload.valueUIKind
                state.valuePicker.editingIndex = payload.editingIndex

                if state.valuePicker.valueArity == 0 {
                    state.valuePicker.values = []
                } else if let existingValues = payload.existingValues {
                    let trimmed = existingValues.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    state.valuePicker.values = Array(trimmed.prefix(state.valuePicker.valueArity))
                    if state.valuePicker.values.count < state.valuePicker.valueArity {
                        state.valuePicker.values.append(contentsOf: Array(
                            repeating: "",
                            count: state.valuePicker.valueArity - state.valuePicker.values.count,
                        ))
                    }
                } else if state.valuePicker.valueArity == 1 {
                    state.valuePicker.values = [""]
                } else {
                    state.valuePicker.values = Array(repeating: "", count: state.valuePicker.valueArity)
                }
                state.valuePicker.isPresented = true
                return .none

            case let .valuePicker(.setValue(index, text)):
                guard !state.isLoadingSearch else { return .none }
                if state.valuePicker.values.indices.contains(index) {
                    state.valuePicker.values[index] = text
                }
                return .none

            case .valuePicker(.commit):
                return .none

            case let .valuePicker(.commitResult(propertyKey, values)):
                guard !state.isLoadingSearch else { return .none }
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                }
                resetValuePicker(state: &state)
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case .valuePicker:
                return .none

            case let .setValue(propertyKey, values):
                guard !state.isLoadingSearch else { return .none }
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                }
                resetValuePicker(state: &state)
                return .none

            case let .searchResponse(.success(response)):
                state.isLoadingSearch = false
                state.lastSearchResponse = response
                state.lastFiltersResponse = nil
                applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                if let startedAt = state.searchStartedAt {
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_search_roundtrip_duration_ms",
                        value: round((Date().timeIntervalSince(startedAt)) * 1000),
                    )
                }
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_search_result",
                    value: 1,
                    tags: ["result": response.itemCount > 0 ? "success" : "empty"],
                )
                state.searchStartedAt = nil
                return .none

            case .searchResponse(.failure):
                state.isLoadingSearch = false
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_search_result",
                    value: 1,
                    tags: ["result": "error"],
                    level: .warn,
                )
                state.searchStartedAt = nil
                return .none

            case let .filtersResponse(.success(response)):
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                state.lastFiltersResponse = response
                applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                if let startedAt = state.filtersStartedAt {
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_filters_roundtrip_duration_ms",
                        value: round((Date().timeIntervalSince(startedAt)) * 1000),
                    )
                }
                state.filtersStartedAt = nil
                return .none

            case .filtersResponse(.failure):
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                state.filtersStartedAt = nil
                return .none
            }
        }
    }
}

private func applyAppliedFilters(
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

private func resetValuePicker(state: inout ComposerFeature.State) {
    state.valuePicker.isPresented = false
    state.valuePicker.propertyKey = nil
    state.valuePicker.operatorCode = nil
    state.valuePicker.values = []
    state.valuePicker.errorMessage = nil
    state.valuePicker.editingIndex = nil
}

private func applyFiltersIfNeeded(
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

private func buildFilters(from state: ComposerFeature.State) -> SearchFiltersPayload {
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

private func updateOperatorOptions(
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    state.operatorOptionsByKey = Dictionary(
        uniqueKeysWithValues: state.conditions.map {
            ($0.propertyKey, registryClient.operatorCodes(for: $0.propertyKey))
        },
    )
}

// swiftlint:enable file_length attributes

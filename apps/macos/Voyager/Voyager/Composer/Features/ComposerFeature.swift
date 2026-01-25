@preconcurrency import ComposableArchitecture
import Foundation
import Logging

// swiftlint:disable file_length type_body_length
private let composerLogger = Logger(label: "Voyager")
struct FilterSnapshot: Equatable {
    let scopes: [String]
    let conditions: [Condition]
}

@Reducer
struct ComposerFeature {
    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var text: String = ""
        var scopes: [String] = []
        var conditions: [Condition] = []
        var operatorOptionsByKey: [String: [String]] = [:]
        var focusRequestID: Int = 0
        var propertyPicker: ConditionPropertyPickerFeature.State = .init()
        var operatorPicker: OperatorPickerFeature.State = .init()
        var valuePicker: ValuePickerFeature.State = .init()
        var history: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
        var redoHistory: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
        var isLoadingSearch: Bool = false
        var isLoadingFilters: Bool = false
        var isFilteringInFlight: Bool = false
        var lastSearchResponse: SearchResponsePayload?
        var lastFiltersResponse: SearchResponsePayload?

        var canUndo: Bool { !history.isEmpty }
        var canRedo: Bool { !redoHistory.isEmpty }

        mutating func pushHistory() {
            history.append(FilterSnapshot(scopes: scopes, conditions: conditions))
            if history.count > 100 {
                history.removeFirst(history.count - 100)
            }
            redoHistory.removeAll()
        }

        mutating func clearHistory() {
            history.removeAll()
            redoHistory.removeAll()
        }
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case setText(String)
        case addScope(path: String)
        case removeScope(path: String)
        case updateScope(oldPath: String, newPath: String)
        case addCondition(propertyKey: String)
        case removeCondition(propertyKey: String)
        case clearAll
        case submit
        case cancelSearch
        case cancelFilters
        case applyFilters
        case saveCollection
        case saveCollectionAs
        case focusQueryField
        case setOperator(propertyKey: String, operatorCode: String)
        case setValue(propertyKey: String, values: [String])
        case replaceConditionProperty(originalKey: String, propertyKey: String)
        case undo
        case redo
        case propertyPicker(ConditionPropertyPickerFeature.Action)
        case operatorPicker(OperatorPickerFeature.Action)
        case valuePicker(ValuePickerFeature.Action)
        case searchResponse(Result<SearchResponsePayload, Error>)
        case filtersResponse(Result<SearchResponsePayload, Error>)
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case search
        case filters
    }

    var body: some Reducer<State, Action> {
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
                return .cancel(id: CancelID.search)

            case .cancelFilters:
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                return .cancel(id: CancelID.filters)

            case .applyFilters:
                state.isLoadingSearch = false
                state.lastSearchResponse = nil
                state.isLoadingFilters = true
                state.isFilteringInFlight = true
                return .concatenate(
                    .cancel(id: CancelID.search),
                    applyFiltersIfNeeded(state: &state, searchClient: searchClient),
                )

            case .saveCollection:
                // TODO: 컬렉션 저장 기능 구현 예정
                return .none

            case .saveCollectionAs:
                // TODO: 컬렉션 저장 기능 구현 예정
                return .none

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
                    valueType: valueType(for: propertyType),
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
                    let typeKey = conditionTypeKey(for: propertyType)
                    let uiValueKind = registryClient.operatorUIKind(
                        for: operatorCode,
                        typeKey: typeKey,
                    )
                    state.conditions[idx].operatorCode = operatorCode
                    state.conditions[idx].operatorLabel = registryClient.operatorLabel(for: operatorCode)
                    state.conditions[idx].operatorValueArity = registryClient.valueArity(for: uiValueKind)
                    state.conditions[idx].operatorValueUIKind = uiValueKind
                    state.conditions[idx].valueType = registryClient.valueType(for: uiValueKind)
                    state.conditions[idx].values = nil
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
                state.conditions[idx].valueType = valueType(for: propertyType)
                state.conditions[idx].values = nil
                updateOperatorOptions(state: &state, registryClient: registryClient)
                state.propertyPicker.editingConditionKey = nil
                state.propertyPicker.isPresented = false
                state.propertyPicker.duplicateMessage = nil
                return .none

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
                state.valuePicker.isPresented = isPresented
                if !isPresented {
                    state.valuePicker.propertyKey = nil
                    state.valuePicker.operatorCode = nil
                    state.valuePicker.values = []
                    state.valuePicker.errorMessage = nil
                    state.valuePicker.editingIndex = nil
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
                state.valuePicker.isPresented = false
                state.valuePicker.propertyKey = nil
                state.valuePicker.operatorCode = nil
                state.valuePicker.errorMessage = nil
                state.valuePicker.editingIndex = nil
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case .valuePicker:
                return .none

            case let .setValue(propertyKey, values):
                guard !state.isLoadingSearch else { return .none }
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                }
                state.valuePicker.isPresented = false
                state.valuePicker.propertyKey = nil
                state.valuePicker.operatorCode = nil
                state.valuePicker.errorMessage = nil
                state.valuePicker.editingIndex = nil
                return .none

            case let .searchResponse(.success(response)):
                state.isLoadingSearch = false
                state.lastSearchResponse = response
                state.lastFiltersResponse = nil
                applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                return .none

            case .searchResponse(.failure):
                state.isLoadingSearch = false
                return .none

            case let .filtersResponse(.success(response)):
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
                state.lastFiltersResponse = response
                applyAppliedFilters(response.appliedFilters, state: &state, registryClient: registryClient)
                return .none

            case .filtersResponse(.failure):
                state.isLoadingFilters = false
                state.isFilteringInFlight = false
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
        guard let encoded = encodeValue(condition: condition, values: values) else { return nil }
        return SearchConditionPayload(propertyKey: condition.propertyKey, operator: op, value: encoded)
    }
    composerLogger.debug(
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

// swiftlint:disable:next cyclomatic_complexity
private func encodeValue(condition: Condition, values: [String]) -> JSONValue? {
    let op = condition.operatorCode?.lowercased()
    if let kind = condition.operatorValueUIKind {
        if let listValue = encodeListValue(kind: kind, values: values) {
            return listValue
        }
    }
    return encodeValueByType(condition: condition, values: values, op: op)
}

private func encodeListValue(kind: String, values: [String]) -> JSONValue? {
    switch kind {
    case "listText":
        return .array(values.map(JSONValue.string))
    case "listNumber":
        let numbers = values.compactMap(Double.init)
        guard numbers.count == values.count else { return nil }
        return .array(numbers.map(JSONValue.number))
    default:
        return nil
    }
}

private func encodeValueByType(
    condition: Condition,
    values: [String],
    op: String?,
) -> JSONValue? {
    switch condition.valueType {
    case "number":
        let numbers = values.compactMap(Double.init)
        guard numbers.count == values.count else { return nil }
        if numbers.count == 1 {
            return .number(numbers[0])
        }
        return .array(numbers.map(JSONValue.number))

    case "boolean":
        guard let first = values.first?.lowercased() else { return nil }
        if first == "true" {
            return .bool(true)
        } else if first == "false" {
            return .bool(false)
        }
        return nil

    case "date", "datetime":
        let formattedValues = values.map { value in
            ValueNormalizerUtils.formatDateOnlyString(value) ?? value
        }
        if formattedValues.count == 1 {
            return .string(formattedValues[0])
        }
        return .array(formattedValues.map(JSONValue.string))

    case "string_list", "string", "unknown":
        if op == "in" || op == "anyof" {
            return .array(values.map(JSONValue.string))
        }
        if values.count == 1 {
            return .string(values[0])
        }
        return .array(values.map(JSONValue.string))

    default:
        if values.count == 1 {
            return .string(values[0])
        }
        return .array(values.map(JSONValue.string))
    }
}

private func valueType(for propertyType: String) -> String {
    switch propertyType {
    case "string", "number", "date", "datetime", "boolean", "string_list":
        propertyType
    default:
        "unknown"
    }
}

private func conditionTypeKey(for rawType: String) -> String {
    switch rawType.lowercased() {
    case "string":
        "string"
    case "number":
        "number"
    case "date", "datetime":
        "date"
    case "boolean":
        "boolean"
    case "string_list":
        "string_list"
    default:
        "unknown"
    }
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

// swiftlint:enable type_body_length

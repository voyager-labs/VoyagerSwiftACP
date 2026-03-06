import ComposableArchitecture
import Foundation

@Reducer
struct ComposerConditionEditingReducer {
    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    typealias State = ComposerState
    typealias Action = ComposerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .addCondition(propertyKey):
                return handleAddCondition(state: &state, propertyKey: propertyKey, registryClient: registryClient)

            case let .removeCondition(propertyKey):
                return handleRemoveCondition(state: &state, propertyKey: propertyKey, registryClient: registryClient)

            case let .setOperator(propertyKey, operatorCode):
                return handleSetOperator(
                    state: &state,
                    propertyKey: propertyKey,
                    operatorCode: operatorCode,
                    registryClient: registryClient,
                    searchClient: searchClient,
                )

            case let .replaceConditionProperty(originalKey, propertyKey):
                return handleReplaceConditionProperty(
                    state: &state,
                    originalKey: originalKey,
                    propertyKey: propertyKey,
                    registryClient: registryClient,
                )

            case let .propertyPicker(.propertyTapped(property)):
                if let editingKey = state.propertyPicker.editingConditionKey {
                    return .send(.replaceConditionProperty(originalKey: editingKey, propertyKey: property))
                }
                return .send(.addCondition(propertyKey: property))

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

            default:
                return .none
            }
        }
    }
}

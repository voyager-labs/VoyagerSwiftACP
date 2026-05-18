import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection

@Reducer
struct ComposerConditionEditingReducer {
    typealias State = ComposerState
    typealias Action = ComposerAction

    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.registryClient)
    var registryClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.addCondition(propertyKey: propertyKey)):
                return handleAddCondition(state: &state, propertyKey: propertyKey, registryClient: registryClient)

            case let .view(.removeCondition(propertyKey: propertyKey)):
                return handleRemoveCondition(
                    state: &state,
                    propertyKey: propertyKey,
                    registryClient: registryClient,
                    searchClient: searchClient,
                )

            case let .view(.setOperator(propertyKey: propertyKey, operatorCode: operatorCode)):
                return handleSetOperator(
                    state: &state,
                    propertyKey: propertyKey,
                    operatorCode: operatorCode,
                    registryClient: registryClient,
                    searchClient: searchClient,
                )

            case let .view(.replaceConditionProperty(originalKey: originalKey, propertyKey: propertyKey)):
                return handleReplaceConditionProperty(
                    state: &state,
                    originalKey: originalKey,
                    propertyKey: propertyKey,
                    registryClient: registryClient,
                )

            case let .view(.setDisplayUnit(propertyKey: propertyKey, unitCode: unitCode)):
                return handleSetDisplayUnit(
                    state: &state,
                    propertyKey: propertyKey,
                    unitCode: unitCode,
                    registryClient: registryClient,
                    searchClient: searchClient,
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

            case .valuePicker(.commit):
                return .none

            case let .valuePicker(.commitResult(propertyKey, values, displayValues, selectedUnitCode)):
                guard !state.isLoadingSearch else { return .none }
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                    if selectedUnitCode != nil {
                        state.conditionDisplayByKey[propertyKey] = .init(
                            values: displayValues,
                            unitValueState: state.valuePicker.unitValueState,
                        )
                    } else {
                        resetConditionDisplayState(propertyKey: propertyKey, state: &state)
                    }
                }
                resetValuePicker(state: &state)
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case .valuePicker:
                return .none

            case let .view(.setValue(propertyKey: propertyKey, values: values)):
                guard !state.isLoadingSearch else { return .none }
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                    syncConditionDisplayState(
                        propertyKey: propertyKey,
                        state: &state,
                        registryClient: registryClient,
                    )
                }
                resetValuePicker(state: &state)
                return .none

            default:
                return .none
            }
        }
    }
}

private func handleAddCondition(
    state: inout ComposerFeature.State,
    propertyKey: String,
    registryClient: RegistryClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    let label = registryClient.labelForKey(propertyKey)
    let propertyType = registryClient.propertyTypeString(for: propertyKey)
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

private func handleRemoveCondition(
    state: inout ComposerFeature.State,
    propertyKey: String,
    registryClient: RegistryClient,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch else { return .none }
    if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
        state.pushHistory()
        state.conditions.removeAll { $0.propertyKey == propertyKey }
        resetConditionDisplayState(propertyKey: propertyKey, state: &state)
        updateOperatorOptions(state: &state, registryClient: registryClient)
    }
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

private func handleSetOperator(
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
        syncConditionDisplayState(
            propertyKey: propertyKey,
            state: &state,
            registryClient: registryClient,
        )

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

private func handleReplaceConditionProperty(
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
    let propertyType = registryClient.propertyTypeString(for: propertyKey)

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
    resetConditionDisplayState(propertyKey: originalKey, state: &state)
    updateOperatorOptions(state: &state, registryClient: registryClient)
    state.propertyPicker.editingConditionKey = nil
    state.propertyPicker.isPresented = false
    state.propertyPicker.duplicateMessage = nil
    return .none
}

private func handleSetDisplayUnit(
    state: inout ComposerFeature.State,
    propertyKey: String,
    unitCode: String,
    registryClient: RegistryClient,
    searchClient: SearchClient,
) -> Effect<ComposerFeature.Action> {
    guard !state.isLoadingSearch,
          let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }),
          let spec = UnitValueUtils.spec(for: propertyKey, registryClient: registryClient)
    else {
        return .none
    }

    guard UnitValueUtils.unitCodes(spec: spec).contains(unitCode) else { return .none }

    let sourceDisplayValues = displayValues(for: state.conditions[idx], state: state)
    let normalizedDisplayValues = UnitValueUtils.strippedDisplayValues(sourceDisplayValues, spec: spec)
    guard let canonicalValues = UnitValueUtils.toCanonicalValues(
        displayValues: normalizedDisplayValues,
        from: unitCode,
        spec: spec,
    ) else {
        return .none
    }

    state.pushHistory()
    state.conditions[idx].values = canonicalValues
    state.conditionDisplayByKey[propertyKey] = .init(
        values: normalizedDisplayValues,
        unitValueState: UnitValuePresentationUtils.makeState(spec: spec, preferredUnitCode: unitCode),
    )
    return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
}

private func resetConditionDisplayState(
    propertyKey: String,
    state: inout ComposerFeature.State,
) {
    state.conditionDisplayByKey.removeValue(forKey: propertyKey)
}

private func syncConditionDisplayState(
    propertyKey: String,
    state: inout ComposerFeature.State,
    registryClient: RegistryClient,
) {
    guard let condition = state.conditions.first(where: { $0.propertyKey == propertyKey }),
          let displayState = defaultDisplayState(for: condition, registryClient: registryClient)
    else {
        resetConditionDisplayState(propertyKey: propertyKey, state: &state)
        return
    }
    state.conditionDisplayByKey[propertyKey] = displayState
}

private func displayValues(
    for condition: Condition,
    state: ComposerFeature.State,
) -> [String] {
    if let display = state.conditionDisplayByKey[condition.propertyKey]?.values {
        return display
    }
    return condition.values ?? []
}

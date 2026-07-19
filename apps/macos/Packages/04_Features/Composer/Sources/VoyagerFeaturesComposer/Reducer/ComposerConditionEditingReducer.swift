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
    @Dependency(\.uuid)
    var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.addCondition(propertyKey)):
                return addCondition(state: &state, propertyKey: propertyKey)

            case let .view(.removeCondition(id)):
                guard !state.isLoadingSearch, state.conditionEditors[id: id] != nil else { return .none }
                state.pushHistory()
                state.conditionEditors.remove(id: id)
                synchronizeDerivedState(state: &state)
                return applyFiltersIfNeeded(state: &state, searchClient: searchClient)

            case let .conditionEditor(.element(id: id, action: .delegate(delegate))):
                return handleDelegate(state: &state, id: id, delegate: delegate)

            case let .conditionEditor(.element(id: id, action: .view(.setPropertyPickerPresented(true)))):
                let siblingKeys = Set(
                    state.conditionEditors
                        .filter { $0.id != id }
                        .map(\.condition.property.key),
                )
                state.conditionEditors[id: id]?.propertyPicker.existingKeys = siblingKeys
                return .none

            case let .propertyPicker(.propertyTapped(propertyKey)):
                return addCondition(state: &state, propertyKey: propertyKey)

            case let .propertyPicker(.setPresented(isPresented)):
                state.propertyPicker.existingKeys = isPresented
                    ? Set(state.conditions.map(\.property.key))
                    : []
                return .none

            case .propertyPicker, .conditionEditor:
                return .none

            default:
                return .none
            }
        }
    }

    private func addCondition(
        state: inout State,
        propertyKey: String,
    ) -> Effect<Action> {
        guard !state.isLoadingSearch else { return .none }
        let condition: Condition
        do {
            condition = try registryClient.resolveCondition(
                propertyKey: propertyKey,
                operatorCode: nil,
                values: nil,
                sourcePayload: nil,
            )
        } catch {
            return .none
        }
        guard !state.conditions.contains(where: { $0.property.key == condition.property.key }) else {
            state.propertyPicker.duplicateMessage = "\"\(condition.property.label)\" is already added."
            return .none
        }
        state.pushHistory()
        state.conditionEditors.append(.init(id: uuid(), condition: condition))
        state.propertyPicker.duplicateMessage = nil
        state.propertyPicker.isPresented = false
        synchronizeDerivedState(state: &state)
        return .none
    }

    private func handleDelegate(
        state: inout State,
        id: UUID,
        delegate: ConditionEditorAction.Delegate,
    ) -> Effect<Action> {
        guard !state.isLoadingSearch, let editor = state.conditionEditors[id: id] else { return .none }
        switch delegate {
        case let .replaceProperty(propertyKey):
            return replaceProperty(state: &state, id: id, editor: editor, propertyKey: propertyKey)

        case let .selectOperator(operatorCode):
            return selectOperator(state: &state, id: id, editor: editor, operatorCode: operatorCode)

        case let .commitValues(values, displayValues, selectedUnitCode):
            return commitValues(
                state: &state,
                id: id,
                editor: editor,
                payload: .init(
                    values: values,
                    displayValues: displayValues,
                    selectedUnitCode: selectedUnitCode,
                ),
            )

        case let .setDisplayUnit(unitCode):
            guard let unitContract = editor.condition.property.unitContract,
                  ConditionUnitConverter.unitCodes(contract: unitContract).contains(unitCode)
            else {
                return .none
            }
            state.pushHistory()
            var unitValueState = editor.displayState?.unitValueState
                ?? .init(contract: unitContract, preferredUnitCode: unitCode)
            unitValueState.selectedUnitCode = unitCode
            state.conditionEditors[id: id] = .init(
                id: editor.id,
                condition: editor.condition,
                displayState: .init(
                    values: editor.displayState?.values ?? editor.condition.values ?? [],
                    unitValueState: unitValueState,
                ),
            )
            synchronizeDerivedState(state: &state)
            return .none
        }
    }

    private func replaceProperty(
        state: inout State,
        id: UUID,
        editor: ConditionEditorState,
        propertyKey: String,
    ) -> Effect<Action> {
        guard editor.condition.property.key != propertyKey else { return .none }
        guard let replacement = try? registryClient.resolveCondition(
            propertyKey: propertyKey, operatorCode: nil, values: nil, sourcePayload: nil,
        ) else { return .none }
        guard !state.conditionEditors
            .contains(where: { $0.id != id && $0.condition.property.key == replacement.property.key })
        else {
            state.conditionEditors[id: id]?.errorMessage = "\"\(replacement.property.label)\" is already added."
            return .none
        }
        state.pushHistory()
        state.conditionEditors[id: id] = .init(id: editor.id, condition: replacement)
        synchronizeDerivedState(state: &state)
        return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
    }

    private func selectOperator(
        state: inout State,
        id: UUID,
        editor: ConditionEditorState,
        operatorCode: String,
    ) -> Effect<Action> {
        guard let replacement = try? registryClient.resolveCondition(
            propertyKey: editor.condition.property.key, operatorCode: operatorCode, values: nil, sourcePayload: nil,
        ) else { return .none }
        state.pushHistory()
        state.conditionEditors[id: id] = .init(id: editor.id, condition: replacement)
        synchronizeDerivedState(state: &state)
        return replacement.operation?.valueContract.count == .fixed(0)
            ? applyFiltersIfNeeded(state: &state, searchClient: searchClient)
            : .none
    }

    private func commitValues(
        state: inout State,
        id: UUID,
        editor: ConditionEditorState,
        payload: ValueCommitPayload,
    ) -> Effect<Action> {
        guard let replacement = try? registryClient.resolveCondition(
            propertyKey: editor.condition.property.key,
            operatorCode: editor.condition.operation?.code,
            values: payload.values,
            sourcePayload: nil,
        ) else { return .none }
        state.pushHistory()
        let displayState = payload.selectedUnitCode.flatMap { _ in
            editor.displayState.map { ConditionDisplayState(
                values: payload.displayValues,
                unitValueState: $0.unitValueState,
            )
            }
        }
        state.conditionEditors[id: id] = .init(id: editor.id, condition: replacement, displayState: displayState)
        synchronizeDerivedState(state: &state)
        return applyFiltersIfNeeded(state: &state, searchClient: searchClient)
    }
}

private struct ValueCommitPayload {
    let values: [String]
    let displayValues: [String]
    let selectedUnitCode: String?
}

private func synchronizeDerivedState(state: inout ComposerState) {
    if state.includeDirectories,
       !state.conditions.contains(where: isFolderInclusiveTagCondition)
    {
        state.includeDirectories = false
    }
}

private func isFolderInclusiveTagCondition(_ condition: Condition) -> Bool {
    condition.isExecutionReady && condition.property.key == "tag_names" && condition.operation?.code == "any"
        && !(condition.values?.isEmpty ?? true)
}

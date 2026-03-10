import ComposableArchitecture
import Foundation

@Reducer
struct ValuePickerFeature {
    @Dependency(\.registryClient)
    var registryClient
    @Dependency(\.finderFavoritesTagClient)
    var finderFavoritesTagClient

    typealias State = ValuePickerState
    typealias Action = ValuePickerAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    resetValuePickerState(state: &state)
                }
                return .none

            case let .prepare(payload):
                state.propertyKey = payload.propertyKey
                state.operatorCode = payload.operatorCode
                state.valueType = payload.valueType
                state.valueArity = max(0, payload.valueArity)
                state.valueUIKind = payload.valueUIKind
                state.isCategoricalProperty =
                    registryClient.propertyTypeString(payload.propertyKey) == "categorical"
                state.tokenInput = ""
                state.finderTagListState = payload.propertyKey == ValuePickerTokenUtils.finderTagPropertyKey
                    ?
                    .init(options: ValuePickerTokenUtils
                        .deduplicatedTagsByName(finderFavoritesTagClient.favoriteTags()))
                    : nil
                state.errorMessage = nil
                state.editingIndex = payload.editingIndex

                let tokenMode = ValuePickerTokenUtils.isTokenMode(
                    isCategoricalProperty: state.isCategoricalProperty,
                    valueUIKind: state.valueUIKind,
                )

                let prepared = prepareValueInputs(
                    valueArity: state.valueArity,
                    existingValues: payload.existingValues,
                    currentValues: state.values,
                    tokenMode: tokenMode,
                )
                state.valueArity = prepared.valueArity
                state.values = prepared.values

                if let spec = resolvedUnitSpec(
                    propertyKey: payload.propertyKey,
                    valueType: payload.valueType,
                    tokenMode: tokenMode,
                ) {
                    let availableUnitCodes = UnitValueUtils.unitCodes(spec: spec)
                    let selectedUnitCode = payload.preferredUnitCode
                        .flatMap { availableUnitCodes.contains($0) ? $0 : nil }
                        ?? UnitValueUtils.defaultDisplayUnitCode(spec: spec)

                    state.unitValueState = .init(
                        selectedUnitCode: selectedUnitCode,
                        availableUnitCodes: availableUnitCodes,
                    )

                    if let existingDisplayValues = payload.existingDisplayValues {
                        let preparedDisplayValues = prepareValueInputs(
                            valueArity: state.valueArity,
                            existingValues: existingDisplayValues,
                            currentValues: state.values,
                            tokenMode: false,
                        )
                        state.valueArity = preparedDisplayValues.valueArity
                        state.values = preparedDisplayValues.values.map {
                            UnitValueUtils.stripUnitSuffixIfNeeded($0, spec: spec)
                        }
                    } else {
                        state.values = state.values.map { raw in
                            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return "" }
                            return UnitValueUtils.fromCanonical(
                                canonicalText: trimmed,
                                to: selectedUnitCode,
                                spec: spec,
                            ) ?? trimmed
                        }
                    }
                } else {
                    state.unitValueState = nil
                }

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                ensureEditableValues(state: &state)
                guard state.values.indices.contains(index) else { return .none }
                state.values[index] = text
                return .none

            case let .selectUnit(unitCode):
                guard let propertyKey = state.propertyKey,
                      let spec = resolvedUnitSpec(
                          propertyKey: propertyKey,
                          valueType: state.valueType,
                          tokenMode: false,
                      ),
                      let unitValueState = state.unitValueState,
                      unitValueState.availableUnitCodes.contains(unitCode)
                else {
                    return .none
                }
                state.unitValueState?.selectedUnitCode = unitCode
                state.errorMessage = nil
                return .none

            case let .setTokenInput(text):
                state.tokenInput = text
                return .none

            case let .appendToken(rawToken):
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else {
                    state.tokenInput = ""
                    return .none
                }

                let normalized = ValuePickerTokenUtils.normalizedTokenKey(token)
                let existing = Set(state.values.map(ValuePickerTokenUtils.normalizedTokenKey))
                guard !existing.contains(normalized) else {
                    state.tokenInput = ""
                    return .none
                }

                state.values.append(token)
                state.values = ValueNormalizerUtils.deduplicatedTokenValues(state.values)
                state.tokenInput = ""
                state.errorMessage = nil
                return .none

            case let .removeToken(rawToken):
                let normalized = ValuePickerTokenUtils.normalizedTokenKey(rawToken)
                state.values.removeAll { ValuePickerTokenUtils.normalizedTokenKey($0) == normalized }
                state.errorMessage = nil
                return .none

            case .commit:
                guard let propertyKey = state.propertyKey,
                      state.operatorCode != nil
                else {
                    return .none
                }

                let tokenMode = ValuePickerTokenUtils.isTokenMode(
                    isCategoricalProperty: state.isCategoricalProperty,
                    valueUIKind: state.valueUIKind,
                )
                let expected = max(state.valueArity, ValueNormalizerUtils.expectedArity(for: state.valueUIKind))
                var displayValues = state.values
                if tokenMode {
                    let token = state.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        let normalized = ValuePickerTokenUtils.normalizedTokenKey(token)
                        let existing = Set(displayValues.map(ValuePickerTokenUtils.normalizedTokenKey))
                        if !existing.contains(normalized) {
                            displayValues.append(token)
                        }
                    }
                    displayValues = ValueNormalizerUtils.deduplicatedTokenValues(displayValues)
                    state.tokenInput = ""
                }

                if expected > 0, displayValues.count < expected {
                    displayValues.append(contentsOf: Array(repeating: "", count: expected - displayValues.count))
                }

                let rawValues: [String]
                let selectedUnitCode = state.unitValueState?.selectedUnitCode
                if let spec = resolvedUnitSpec(
                    propertyKey: propertyKey,
                    valueType: state.valueType,
                    tokenMode: tokenMode,
                ), let selectedUnitCode {
                    guard let canonicalValues = UnitValueUtils.toCanonicalValues(
                        displayValues: displayValues,
                        from: selectedUnitCode,
                        spec: spec,
                    ) else {
                        state.errorMessage = "Enter a valid number."
                        return .none
                    }
                    rawValues = canonicalValues
                    displayValues = UnitValueUtils.strippedDisplayValues(displayValues, spec: spec)
                } else {
                    rawValues = displayValues
                }

                let result = ValueNormalizerUtils.normalize(
                    kind: state.valueUIKind,
                    rawValues: rawValues,
                    editingIndex: state.editingIndex,
                )

                if let error = result.errorMessage {
                    state.errorMessage = error
                    result.resetIndices
                        .filter { state.values.indices.contains($0) }
                        .forEach { state.values[$0] = "" }
                    if expected > 0, state.values.count < expected {
                        state.values.append(contentsOf: Array(repeating: "", count: expected - state.values.count))
                    }
                    return .none
                }

                state.errorMessage = nil
                if tokenMode {
                    state.values = ValueNormalizerUtils.deduplicatedTokenValues(displayValues)
                }
                return .send(
                    .commitResult(
                        propertyKey: propertyKey,
                        values: result.values ?? [],
                        displayValues: displayValues,
                        selectedUnitCode: state.unitValueState?.selectedUnitCode,
                    ),
                )

            case .commitResult:
                return .none
            }
        }
    }
}

private func resetValuePickerState(state: inout ValuePickerState) {
    state.propertyKey = nil
    state.operatorCode = nil
    state.isCategoricalProperty = false
    state.values = [""]
    state.unitValueState = nil
    state.tokenInput = ""
    state.finderTagListState = nil
    state.errorMessage = nil
    state.editingIndex = nil
    state.valueType = "string"
    state.valueUIKind = "singleText"
    state.valueArity = 1
}

private func ensureEditableValues(state: inout ValuePickerState) {
    let count = max(state.valueArity, 1)
    if state.values.count < count {
        state.values = Array(repeating: "", count: count)
    }
}

private func prepareValueInputs(
    valueArity: Int,
    existingValues: [String]?,
    currentValues: [String],
    tokenMode: Bool,
) -> (valueArity: Int, values: [String]) {
    let normalizedArity = max(0, valueArity)
    guard normalizedArity > 0 else { return (0, []) }

    if let existingValues {
        let trimmed = existingValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalized = tokenMode ? ValueNormalizerUtils.deduplicatedTokenValues(trimmed) : trimmed
        let effectiveArity = max(normalizedArity, normalized.count)
        var values = Array(normalized.prefix(effectiveArity))
        if values.count < effectiveArity {
            values.append(contentsOf: Array(repeating: "", count: effectiveArity - values.count))
        }
        return (effectiveArity, values)
    }

    if normalizedArity == 1 {
        return (1, [currentValues.first ?? ""])
    }

    return (normalizedArity, Array(repeating: "", count: normalizedArity))
}

private func resolvedUnitSpec(
    propertyKey: String,
    valueType: String,
    tokenMode: Bool,
) -> UnitValueUtils.UnitSpec? {
    guard !tokenMode,
          UnitValueUtils.supportsUnits(propertyKey: propertyKey, valueType: valueType)
    else {
        return nil
    }
    return UnitValueUtils.spec(for: propertyKey)
}

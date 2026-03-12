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

                let prepared = prepareValueInputs(
                    valueArity: state.valueArity,
                    existingValues: payload.existingValues,
                    currentValues: state.values,
                    tokenMode: ValuePickerTokenUtils.isTokenMode(
                        isCategoricalProperty: state.isCategoricalProperty,
                        valueUIKind: state.valueUIKind,
                    ),
                )
                state.valueArity = prepared.valueArity
                state.values = prepared.values

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                ensureEditableValues(state: &state)
                guard state.values.indices.contains(index) else { return .none }
                state.values[index] = text
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

                let expected = max(state.valueArity, ValueNormalizerUtils.expectedArity(for: state.valueUIKind))
                var paddedValues = state.values
                if ValuePickerTokenUtils.isTokenMode(
                    isCategoricalProperty: state.isCategoricalProperty,
                    valueUIKind: state.valueUIKind,
                ) {
                    let token = state.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        let normalized = ValuePickerTokenUtils.normalizedTokenKey(token)
                        let existing = Set(paddedValues.map(ValuePickerTokenUtils.normalizedTokenKey))
                        if !existing.contains(normalized) {
                            paddedValues.append(token)
                        }
                    }
                    paddedValues = ValueNormalizerUtils.deduplicatedTokenValues(paddedValues)
                    state.tokenInput = ""
                }
                if expected > 0, paddedValues.count < expected {
                    paddedValues.append(contentsOf: Array(repeating: "", count: expected - paddedValues.count))
                }

                let result = ValueNormalizerUtils.normalize(
                    kind: state.valueUIKind,
                    rawValues: paddedValues,
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
                guard let committedValues = result.values else {
                    return .none
                }
                if ValuePickerTokenUtils.isTokenMode(
                    isCategoricalProperty: state.isCategoricalProperty,
                    valueUIKind: state.valueUIKind,
                ) {
                    state.values = ValueNormalizerUtils.deduplicatedTokenValues(state.values)
                }
                return .send(
                    .commitResult(
                        propertyKey: propertyKey,
                        values: committedValues,
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

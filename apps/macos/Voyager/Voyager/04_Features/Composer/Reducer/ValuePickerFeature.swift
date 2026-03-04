import ComposableArchitecture
import Foundation

@Reducer
struct ValuePickerFeature {
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
                state.errorMessage = nil
                state.editingIndex = payload.editingIndex

                let prepared = prepareValueInputs(
                    valueArity: state.valueArity,
                    existingValues: payload.existingValues,
                    currentValues: state.values,
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

            case .commit:
                guard let propertyKey = state.propertyKey,
                      state.operatorCode != nil
                else {
                    return .none
                }

                let expected = max(state.valueArity, ValueNormalizerUtils.expectedArity(for: state.valueUIKind))
                var paddedValues = state.values
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
                return .send(
                    .commitResult(
                        propertyKey: propertyKey,
                        values: result.values ?? [],
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
    state.values = [""]
    state.errorMessage = nil
    state.editingIndex = nil
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
) -> (valueArity: Int, values: [String]) {
    let normalizedArity = max(0, valueArity)
    guard normalizedArity > 0 else { return (0, []) }

    if let existingValues {
        let trimmed = existingValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let effectiveArity = max(normalizedArity, trimmed.count)
        var values = Array(trimmed.prefix(effectiveArity))
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

import ComposableArchitecture
import Foundation

@Reducer
struct ValuePickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var propertyKey: String?
        var operatorOption: OperatorOption?
        var valueType: ValueType = .string
        var valueUIKind: ValueUIKind = .singleText
        var valueArity: Int = 1
        var values: [String] = [""]
        var errorMessage: String?
        var editingIndex: Int?
    }

    struct PreparePayload: Sendable, Equatable {
        let propertyKey: String
        let operatorOption: OperatorOption
        let valueType: ValueType
        let valueUIKind: ValueUIKind
        let existingValues: [String]?
        let editingIndex: Int?
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case prepare(PreparePayload)
        case setValue(index: Int, text: String)
        case commit
        case commitResult(propertyKey: String, values: [String])
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    state.propertyKey = nil
                    state.operatorOption = nil
                    state.values = [""]
                    state.errorMessage = nil
                    state.editingIndex = nil
                    state.valueUIKind = .singleText
                    state.valueArity = 1
                }
                return .none

            case let .prepare(payload):
                state.propertyKey = payload.propertyKey
                state.operatorOption = payload.operatorOption
                state.valueType = payload.valueType
                state.valueArity = max(0, payload.operatorOption.valueArity)
                state.valueUIKind = payload.valueUIKind
                state.errorMessage = nil
                state.editingIndex = payload.editingIndex

                if state.valueArity == 0 {
                    state.values = []
                } else if let existingValues = payload.existingValues {
                    let trimmed = existingValues.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    state.valueArity = max(state.valueArity, trimmed.count)
                    state.values = Array(trimmed.prefix(state.valueArity))
                    if state.values.count < state.valueArity {
                        state.values.append(
                            contentsOf: Array(
                                repeating: "",
                                count: state.valueArity - state.values.count,
                            ),
                        )
                    }
                } else if state.valueArity == 1 {
                    state.values = [state.values.first ?? ""]
                } else {
                    state.values = Array(repeating: "", count: state.valueArity)
                }

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                if state.values.count < max(state.valueArity, 1) {
                    state.values = Array(
                        repeating: "",
                        count: max(state.valueArity, 1),
                    )
                }
                guard state.values.indices.contains(index) else { return .none }
                state.values[index] = text
                return .none

            case .commit:
                guard let propertyKey = state.propertyKey,
                      state.operatorOption != nil
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

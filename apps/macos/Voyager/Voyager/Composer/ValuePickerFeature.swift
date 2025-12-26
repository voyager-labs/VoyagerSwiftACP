import ComposableArchitecture
import Foundation

enum ValueType: String, Sendable, Equatable {
    case string
    case number
    case date
    case boolean
    case array
    case unknown
}

@Reducer
struct ValuePickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var propertyKey: String?
        var operatorOption: OperatorOption?
        var valueType: ValueType = .string
        var valueArity: Int = 1
        var values: [String] = [""]
        var errorMessage: String?
        var editingIndex: Int?
    }

    struct PreparePayload: Sendable, Equatable {
        let propertyKey: String
        let operatorOption: OperatorOption
        let valueType: ValueType
        let existingValues: [String]?
        let editingIndex: Int?
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case prepare(PreparePayload)
        case setValue(index: Int, text: String)
        case commit
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
                }
                return .none

            case let .prepare(payload):
                state.propertyKey = payload.propertyKey
                state.operatorOption = payload.operatorOption
                state.valueType = payload.valueType
                state.valueArity = max(0, payload.operatorOption.valueArity)
                state.errorMessage = nil
                state.editingIndex = payload.editingIndex

                if state.valueArity == 0 {
                    state.values = []
                } else if let existingValues = payload.existingValues {
                    let trimmed = existingValues.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    state.values = Array(trimmed.prefix(state.valueArity))
                    if state.values.count < state.valueArity {
                        state.values.append(contentsOf: Array(
                            repeating: "",
                            count: state.valueArity - state.values.count,
                        ))
                    }
                } else if state.valueArity == 1 {
                    state.values = [state.values.first ?? ""]
                } else {
                    // arity 2 이상은 최소 2칸 확보
                    state.values = Array(repeating: "", count: state.valueArity)
                }

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                // 값 배열이 비어있을 수 있으므로 아리티에 맞춰 길이 보정
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
                return .none
            }
        }
    }
}
